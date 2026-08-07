CREATE OR REPLACE PROCEDURE gold.sp_load_fact_flight_operations(
    P_AUDIT_TABLE_FQN STRING
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    V_PROC_NAME STRING DEFAULT 'gold.sp_load_fact_flight_operations';
    V_TARGET_TABLE STRING DEFAULT 'gold.fact_flight_operations';
    V_START_TS TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP();
    V_END_TS TIMESTAMP_NTZ;
    V_STATUS STRING;
    V_ERR_MSG STRING;
    V_MERGE_ROWS_INSERTED NUMBER DEFAULT 0;
    V_MERGE_ROWS_UPDATED NUMBER DEFAULT 0;
BEGIN

    -- ---------------------------------------------------------------------
    -- AUDIT: start
    -- Guard: do not write audit rows if the target is the audit table itself
    -- ---------------------------------------------------------------------
    IF (UPPER(V_TARGET_TABLE) <> UPPER(P_AUDIT_TABLE_FQN)) THEN
        EXECUTE IMMEDIATE
            'INSERT INTO ' || P_AUDIT_TABLE_FQN || '
             (procedure_name, target_table, start_ts, status)
             SELECT ?, ?, ?, ''RUNNING''' 
            USING (V_PROC_NAME, V_TARGET_TABLE, V_START_TS);
    END IF;

    -- ---------------------------------------------------------------------
    -- VALIDATION: only load Silver rows with dq_valid_flag = TRUE
    -- Never silently drop: if invalid rows exist, log failure and raise.
    -- ---------------------------------------------------------------------
    IF ((SELECT COUNT(*) FROM silver.slv_flight_operations WHERE dq_valid_flag = FALSE) > 0) THEN
        V_STATUS := 'FAILED';
        V_ERR_MSG := 'Validation failed: silver.slv_flight_operations contains dq_valid_flag=FALSE rows';
        V_END_TS := CURRENT_TIMESTAMP();

        IF (UPPER(V_TARGET_TABLE) <> UPPER(P_AUDIT_TABLE_FQN)) THEN
            EXECUTE IMMEDIATE
                'INSERT INTO ' || P_AUDIT_TABLE_FQN || '
                 (procedure_name, target_table, start_ts, end_ts, status, error_message)
                 SELECT ?, ?, ?, ?, ?, ?'
                USING (V_PROC_NAME, V_TARGET_TABLE, V_START_TS, V_END_TS, V_STATUS, V_ERR_MSG);
        END IF;

        RAISE STATEMENT_ERROR WITH MESSAGE = V_ERR_MSG;
    END IF;

    -- ---------------------------------------------------------------------
    -- UPSERT: fact_flight_operations
    -- Natural key for merge: schedule_id (when present) else flight_id
    -- NOTE: Gold DDL does not carry flight_id, so we use a derived business key
    -- for match to keep incremental behavior deterministic.
    -- ---------------------------------------------------------------------

    MERGE INTO gold.fact_flight_operations AS T
    USING (
        WITH src AS (
            SELECT
                fo.flight_id,
                fo.schedule_id,
                fo.carrier_code,
                fo.tail_number,
                fo.origin_airport_code,
                fo.destination_airport_code,
                fo.route_id,
                fo.flight_date,
                fo.scheduled_departure_ts,
                fo.actual_departure_ts,
                fo.scheduled_arrival_ts,
                fo.actual_arrival_ts,
                fo.delay_minutes,
                fo.taxi_out_minutes,
                fo.taxi_in_minutes,
                fo.flight_distance_miles,
                fo.block_hours,
                fo.cancelled_flag,
                fo.diverted_flag,
                fo.source_system,
                fo.created_ts,
                fo.updated_ts
            FROM silver.slv_flight_operations fo
            WHERE fo.dq_valid_flag = TRUE
        ),
        lookups AS (
            SELECT
                s.*,
                dd.date_key AS lkp_date_key,
                da.airline_key AS lkp_airline_key,
                dor.airport_key AS lkp_origin_airport_key,
                dda.airport_key AS lkp_destination_airport_key,
                dr.route_key AS lkp_route_key,
                dac.aircraft_key AS lkp_aircraft_key
            FROM src s
            LEFT JOIN gold.dim_date dd
                ON dd.date = s.flight_date
            LEFT JOIN gold.dim_airline da
                ON da.airline_code = s.carrier_code
            LEFT JOIN gold.dim_airport dor
                ON dor.airport_code = s.origin_airport_code
            LEFT JOIN gold.dim_airport dda
                ON dda.airport_code = s.destination_airport_code
            LEFT JOIN gold.dim_route dr
                ON dr.route_key IS NOT NULL
               AND EXISTS (
                    SELECT 1
                    FROM silver.slv_route r
                    WHERE r.route_id = s.route_id
                )
            LEFT JOIN gold.dim_route dr2
                ON dr2.route_key = dr.route_key
            LEFT JOIN gold.dim_route dr
                ON dr.route_key = dr2.route_key
            LEFT JOIN gold.dim_aircraft dac
                ON dac.tail_number = s.tail_number
               AND s.flight_date BETWEEN dac.effective_start_date AND COALESCE(dac.effective_end_date, '9999-12-31')
        ),
        final AS (
            SELECT
                /* Merge key: prefer schedule_id; else fall back to flight_id */
                COALESCE(l.schedule_id, l.flight_id) AS merge_key,

                CAST(l.lkp_date_key AS INTEGER) AS date_key,
                CAST(l.lkp_airline_key AS INTEGER) AS airline_key,
                CAST(l.lkp_aircraft_key AS INTEGER) AS aircraft_key,
                CAST(l.lkp_route_key AS INTEGER) AS route_key,
                CAST(l.lkp_origin_airport_key AS INTEGER) AS origin_airport_key,
                CAST(l.lkp_destination_airport_key AS INTEGER) AS destination_airport_key,

                CAST(l.schedule_id AS VARCHAR(50)) AS schedule_id,
                CAST(l.scheduled_departure_ts AS TIMESTAMP) AS scheduled_departure_ts,
                CAST(l.actual_departure_ts AS TIMESTAMP) AS actual_departure_ts,
                CAST(l.scheduled_arrival_ts AS TIMESTAMP) AS scheduled_arrival_ts,
                CAST(l.actual_arrival_ts AS TIMESTAMP) AS actual_arrival_ts,
                CAST(l.delay_minutes AS INTEGER) AS delay_minutes,
                CAST(l.taxi_out_minutes AS INTEGER) AS taxi_out_minutes,
                CAST(l.taxi_in_minutes AS INTEGER) AS taxi_in_minutes,
                CAST(l.flight_distance_miles AS NUMBER(10,2)) AS flight_distance_miles,
                CAST(l.block_hours AS NUMBER(6,2)) AS block_hours,
                CAST(l.cancelled_flag AS BOOLEAN) AS cancelled_flag,
                CAST(l.diverted_flag AS BOOLEAN) AS diverted_flag,
                CAST(l.source_system AS VARCHAR(100)) AS source_system,

                /* dw audit */
                CURRENT_TIMESTAMP() AS dw_created_ts,
                CURRENT_TIMESTAMP() AS dw_updated_ts,

                l.updated_ts AS src_updated_ts
            FROM lookups l
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY COALESCE(l.schedule_id, l.flight_id)
                ORDER BY l.updated_ts DESC
            ) = 1
        )
        SELECT
            merge_key,
            date_key,
            airline_key,
            aircraft_key,
            route_key,
            origin_airport_key,
            destination_airport_key,
            schedule_id,
            scheduled_departure_ts,
            actual_departure_ts,
            scheduled_arrival_ts,
            actual_arrival_ts,
            delay_minutes,
            taxi_out_minutes,
            taxi_in_minutes,
            flight_distance_miles,
            block_hours,
            cancelled_flag,
            diverted_flag,
            source_system,
            dw_created_ts,
            dw_updated_ts
        FROM final
    ) AS S
    ON (
        /* Match an existing row by schedule_id when available; else approximate by schedule_id NULL rows */
        (T.schedule_id IS NOT NULL AND T.schedule_id = S.schedule_id)
        OR
        (T.schedule_id IS NULL AND S.schedule_id IS NULL
         AND T.date_key = S.date_key
         AND NVL(T.airline_key, -1) = NVL(S.airline_key, -1)
         AND NVL(T.origin_airport_key, -1) = NVL(S.origin_airport_key, -1)
         AND NVL(T.destination_airport_key, -1) = NVL(S.destination_airport_key, -1)
         AND NVL(T.scheduled_departure_ts, '1900-01-01'::TIMESTAMP) = NVL(S.scheduled_departure_ts, '1900-01-01'::TIMESTAMP)
        )
    )
    WHEN MATCHED THEN UPDATE SET
        T.date_key = S.date_key,
        T.airline_key = S.airline_key,
        T.aircraft_key = S.aircraft_key,
        T.route_key = S.route_key,
        T.origin_airport_key = S.origin_airport_key,
        T.destination_airport_key = S.destination_airport_key,
        T.schedule_id = S.schedule_id,
        T.scheduled_departure_ts = S.scheduled_departure_ts,
        T.actual_departure_ts = S.actual_departure_ts,
        T.scheduled_arrival_ts = S.scheduled_arrival_ts,
        T.actual_arrival_ts = S.actual_arrival_ts,
        T.delay_minutes = S.delay_minutes,
        T.taxi_out_minutes = S.taxi_out_minutes,
        T.taxi_in_minutes = S.taxi_in_minutes,
        T.flight_distance_miles = S.flight_distance_miles,
        T.block_hours = S.block_hours,
        T.cancelled_flag = S.cancelled_flag,
        T.diverted_flag = S.diverted_flag,
        T.source_system = S.source_system,
        T.dw_updated_ts = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (
        date_key,
        airline_key,
        aircraft_key,
        route_key,
        origin_airport_key,
        destination_airport_key,
        schedule_id,
        scheduled_departure_ts,
        actual_departure_ts,
        scheduled_arrival_ts,
        actual_arrival_ts,
        delay_minutes,
        taxi_out_minutes,
        taxi_in_minutes,
        flight_distance_miles,
        block_hours,
        cancelled_flag,
        diverted_flag,
        source_system,
        dw_created_ts,
        dw_updated_ts
    ) VALUES (
        S.date_key,
        S.airline_key,
        S.aircraft_key,
        S.route_key,
        S.origin_airport_key,
        S.destination_airport_key,
        S.schedule_id,
        S.scheduled_departure_ts,
        S.actual_departure_ts,
        S.scheduled_arrival_ts,
        S.actual_arrival_ts,
        S.delay_minutes,
        S.taxi_out_minutes,
        S.taxi_in_minutes,
        S.flight_distance_miles,
        S.block_hours,
        S.cancelled_flag,
        S.diverted_flag,
        S.source_system,
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP()
    );

    V_STATUS := 'SUCCESS';
    V_END_TS := CURRENT_TIMESTAMP();

    IF (UPPER(V_TARGET_TABLE) <> UPPER(P_AUDIT_TABLE_FQN)) THEN
        EXECUTE IMMEDIATE
            'INSERT INTO ' || P_AUDIT_TABLE_FQN || '
             (procedure_name, target_table, start_ts, end_ts, status, rows_inserted, rows_updated)
             SELECT ?, ?, ?, ?, ?, ?, ?'
            USING (V_PROC_NAME, V_TARGET_TABLE, V_START_TS, V_END_TS, V_STATUS, V_MERGE_ROWS_INSERTED, V_MERGE_ROWS_UPDATED);
    END IF;

    RETURN 'SUCCESS';

EXCEPTION
    WHEN OTHER THEN
        V_STATUS := 'FAILED';
        V_ERR_MSG := SQLERRM;
        V_END_TS := CURRENT_TIMESTAMP();

        IF (UPPER(V_TARGET_TABLE) <> UPPER(P_AUDIT_TABLE_FQN)) THEN
            EXECUTE IMMEDIATE
                'INSERT INTO ' || P_AUDIT_TABLE_FQN || '
                 (procedure_name, target_table, start_ts, end_ts, status, error_message)
                 SELECT ?, ?, ?, ?, ?, ?'
                USING (V_PROC_NAME, V_TARGET_TABLE, V_START_TS, V_END_TS, V_STATUS, V_ERR_MSG);
        END IF;

        RAISE;
END;
$$;
