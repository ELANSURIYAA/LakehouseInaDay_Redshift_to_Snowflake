CREATE OR REPLACE PROCEDURE gold.sp_load_fact_flight_operations(
    P_AUDIT_TABLE_FQN STRING,
    P_SOURCE_SCHEMA STRING DEFAULT 'SILVER',
    P_TARGET_SCHEMA STRING DEFAULT 'GOLD'
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_PROC_NAME STRING DEFAULT 'gold.sp_load_fact_flight_operations';
    V_TARGET_TABLE STRING;
    V_ROWS_AFFECTED NUMBER;
    V_START_TS TIMESTAMP_NTZ;
BEGIN
    V_TARGET_TABLE := P_TARGET_SCHEMA || '.FACT_FLIGHT_OPERATIONS';
    V_START_TS := CURRENT_TIMESTAMP();

    -- Pre-step audit (guard against recursive logging)
    IF (UPPER(V_TARGET_TABLE) <> UPPER(P_AUDIT_TABLE_FQN)) THEN
        EXECUTE IMMEDIATE
            'INSERT INTO ' || P_AUDIT_TABLE_FQN || ' (procedure_name, target_table, start_ts, status) VALUES (?, ?, ?, ?)'
            USING (V_PROC_NAME, V_TARGET_TABLE, V_START_TS, 'RUNNING');
    END IF;

    -- Data quality assertions (do not silently drop invalid rows)
    IF (
        (SELECT COUNT(*)
         FROM IDENTIFIER(P_SOURCE_SCHEMA || '.SLV_FLIGHT_OPERATIONS') s
         WHERE COALESCE(s.DQ_VALID_FLAG, FALSE) <> TRUE) > 0
    ) THEN
        IF (UPPER(V_TARGET_TABLE) <> UPPER(P_AUDIT_TABLE_FQN)) THEN
            EXECUTE IMMEDIATE
                'INSERT INTO ' || P_AUDIT_TABLE_FQN || ' (procedure_name, target_table, start_ts, end_ts, status, error_message) VALUES (?, ?, ?, ?, ?, ?)'
                USING (V_PROC_NAME, V_TARGET_TABLE, V_START_TS, CURRENT_TIMESTAMP(), 'FAILED', 'DQ validation failed: SLV_FLIGHT_OPERATIONS contains dq_valid_flag = FALSE rows.');
        END IF;
        RAISE STATEMENT_ERROR USING MESSAGE = 'DQ validation failed: SLV_FLIGHT_OPERATIONS contains dq_valid_flag = FALSE rows.';
    END IF;

    MERGE INTO IDENTIFIER(P_TARGET_SCHEMA || '.FACT_FLIGHT_OPERATIONS') tgt
    USING (
        WITH src AS (
            SELECT
                s.FLIGHT_ID,
                s.SCHEDULE_ID,
                s.FLIGHT_DATE,
                s.CARRIER_CODE,
                s.TAIL_NUMBER,
                s.ROUTE_ID,
                s.ORIGIN_AIRPORT_CODE,
                s.DESTINATION_AIRPORT_CODE,
                s.SCHEDULED_DEPARTURE_TS,
                s.ACTUAL_DEPARTURE_TS,
                s.SCHEDULED_ARRIVAL_TS,
                s.ACTUAL_ARRIVAL_TS,
                s.DELAY_MINUTES,
                s.TAXI_OUT_MINUTES,
                s.TAXI_IN_MINUTES,
                s.FLIGHT_DISTANCE_MILES,
                s.BLOCK_HOURS,
                s.CANCELLED_FLAG,
                s.DIVERTED_FLAG,
                s.SOURCE_SYSTEM,
                s.CREATED_TS,
                s.UPDATED_TS
            FROM IDENTIFIER(P_SOURCE_SCHEMA || '.SLV_FLIGHT_OPERATIONS') s
            WHERE COALESCE(s.DQ_VALID_FLAG, FALSE) = TRUE
        ),
        dedup AS (
            SELECT *
            FROM src
            QUALIFY ROW_NUMBER() OVER (PARTITION BY FLIGHT_ID ORDER BY UPDATED_TS DESC) = 1
        ),
        lk AS (
            SELECT
                d.FLIGHT_ID,
                dd.DATE_KEY AS DATE_KEY,
                da.AIRLINE_KEY AS AIRLINE_KEY,
                dac.AIRCRAFT_KEY AS AIRCRAFT_KEY,
                dr.ROUTE_KEY AS ROUTE_KEY,
                doa.AIRPORT_KEY AS ORIGIN_AIRPORT_KEY,
                dda.AIRPORT_KEY AS DESTINATION_AIRPORT_KEY,
                d.SCHEDULE_ID,
                d.SCHEDULED_DEPARTURE_TS,
                d.ACTUAL_DEPARTURE_TS,
                d.SCHEDULED_ARRIVAL_TS,
                d.ACTUAL_ARRIVAL_TS,
                d.DELAY_MINUTES,
                d.TAXI_OUT_MINUTES,
                d.TAXI_IN_MINUTES,
                d.FLIGHT_DISTANCE_MILES,
                d.BLOCK_HOURS,
                d.CANCELLED_FLAG,
                d.DIVERTED_FLAG,
                d.SOURCE_SYSTEM,
                d.CREATED_TS,
                d.UPDATED_TS
            FROM dedup d
            LEFT JOIN IDENTIFIER(P_TARGET_SCHEMA || '.DIM_DATE') dd
                ON dd.DATE = d.FLIGHT_DATE
            LEFT JOIN IDENTIFIER(P_TARGET_SCHEMA || '.DIM_AIRLINE') da
                ON da.AIRLINE_CODE = d.CARRIER_CODE
            -- SKIPPED: gold.dim_route.route_key — Mapping requires lookup by slv_route.route_id but dim_route DDL has no route_id/route_code natural key column.
            LEFT JOIN IDENTIFIER(P_TARGET_SCHEMA || '.DIM_ROUTE') dr
                ON 1=0
            LEFT JOIN IDENTIFIER(P_TARGET_SCHEMA || '.DIM_AIRPORT') doa
                ON doa.AIRPORT_CODE = d.ORIGIN_AIRPORT_CODE
            LEFT JOIN IDENTIFIER(P_TARGET_SCHEMA || '.DIM_AIRPORT') dda
                ON dda.AIRPORT_CODE = d.DESTINATION_AIRPORT_CODE
            LEFT JOIN IDENTIFIER(P_TARGET_SCHEMA || '.DIM_AIRCRAFT') dac
                ON dac.TAIL_NUMBER = d.TAIL_NUMBER
               AND d.FLIGHT_DATE BETWEEN dac.EFFECTIVE_START_DATE AND COALESCE(dac.EFFECTIVE_END_DATE, '9999-12-31')
        )
        SELECT
            FLIGHT_ID,
            DATE_KEY,
            AIRLINE_KEY,
            AIRCRAFT_KEY,
            ROUTE_KEY,
            ORIGIN_AIRPORT_KEY,
            DESTINATION_AIRPORT_KEY,
            SCHEDULE_ID,
            SCHEDULED_DEPARTURE_TS,
            ACTUAL_DEPARTURE_TS,
            SCHEDULED_ARRIVAL_TS,
            ACTUAL_ARRIVAL_TS,
            DELAY_MINUTES,
            TAXI_OUT_MINUTES,
            TAXI_IN_MINUTES,
            FLIGHT_DISTANCE_MILES,
            BLOCK_HOURS,
            CANCELLED_FLAG,
            DIVERTED_FLAG,
            SOURCE_SYSTEM,
            CREATED_TS,
            UPDATED_TS
        FROM lk
    ) src
    ON tgt.SCHEDULE_ID = src.SCHEDULE_ID
       AND tgt.DATE_KEY = src.DATE_KEY
    WHEN MATCHED THEN UPDATE SET
        tgt.DATE_KEY = src.DATE_KEY,
        tgt.AIRLINE_KEY = src.AIRLINE_KEY,
        tgt.AIRCRAFT_KEY = src.AIRCRAFT_KEY,
        tgt.ROUTE_KEY = src.ROUTE_KEY,
        tgt.ORIGIN_AIRPORT_KEY = src.ORIGIN_AIRPORT_KEY,
        tgt.DESTINATION_AIRPORT_KEY = src.DESTINATION_AIRPORT_KEY,
        tgt.SCHEDULED_DEPARTURE_TS = src.SCHEDULED_DEPARTURE_TS,
        tgt.ACTUAL_DEPARTURE_TS = src.ACTUAL_DEPARTURE_TS,
        tgt.SCHEDULED_ARRIVAL_TS = src.SCHEDULED_ARRIVAL_TS,
        tgt.ACTUAL_ARRIVAL_TS = src.ACTUAL_ARRIVAL_TS,
        tgt.DELAY_MINUTES = src.DELAY_MINUTES,
        tgt.TAXI_OUT_MINUTES = src.TAXI_OUT_MINUTES,
        tgt.TAXI_IN_MINUTES = src.TAXI_IN_MINUTES,
        tgt.FLIGHT_DISTANCE_MILES = src.FLIGHT_DISTANCE_MILES,
        tgt.BLOCK_HOURS = src.BLOCK_HOURS,
        tgt.CANCELLED_FLAG = src.CANCELLED_FLAG,
        tgt.DIVERTED_FLAG = src.DIVERTED_FLAG,
        tgt.SOURCE_SYSTEM = src.SOURCE_SYSTEM,
        tgt.DW_UPDATED_TS = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (
        DATE_KEY,
        AIRLINE_KEY,
        AIRCRAFT_KEY,
        ROUTE_KEY,
        ORIGIN_AIRPORT_KEY,
        DESTINATION_AIRPORT_KEY,
        SCHEDULE_ID,
        SCHEDULED_DEPARTURE_TS,
        ACTUAL_DEPARTURE_TS,
        SCHEDULED_ARRIVAL_TS,
        ACTUAL_ARRIVAL_TS,
        DELAY_MINUTES,
        TAXI_OUT_MINUTES,
        TAXI_IN_MINUTES,
        FLIGHT_DISTANCE_MILES,
        BLOCK_HOURS,
        CANCELLED_FLAG,
        DIVERTED_FLAG,
        SOURCE_SYSTEM,
        DW_CREATED_TS,
        DW_UPDATED_TS
    ) VALUES (
        src.DATE_KEY,
        src.AIRLINE_KEY,
        src.AIRCRAFT_KEY,
        src.ROUTE_KEY,
        src.ORIGIN_AIRPORT_KEY,
        src.DESTINATION_AIRPORT_KEY,
        src.SCHEDULE_ID,
        src.SCHEDULED_DEPARTURE_TS,
        src.ACTUAL_DEPARTURE_TS,
        src.SCHEDULED_ARRIVAL_TS,
        src.ACTUAL_ARRIVAL_TS,
        src.DELAY_MINUTES,
        src.TAXI_OUT_MINUTES,
        src.TAXI_IN_MINUTES,
        src.FLIGHT_DISTANCE_MILES,
        src.BLOCK_HOURS,
        src.CANCELLED_FLAG,
        src.DIVERTED_FLAG,
        src.SOURCE_SYSTEM,
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP()
    );

    V_ROWS_AFFECTED := (SELECT COALESCE(SUM(rows_affected),0) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));

    -- Post-step audit
    IF (UPPER(V_TARGET_TABLE) <> UPPER(P_AUDIT_TABLE_FQN)) THEN
        EXECUTE IMMEDIATE
            'INSERT INTO ' || P_AUDIT_TABLE_FQN || ' (procedure_name, target_table, start_ts, end_ts, status, rows_affected) VALUES (?, ?, ?, ?, ?, ?)'
            USING (V_PROC_NAME, V_TARGET_TABLE, V_START_TS, CURRENT_TIMESTAMP(), 'SUCCESS', V_ROWS_AFFECTED);
    END IF;

    RETURN OBJECT_CONSTRUCT('status','SUCCESS','rows_affected',V_ROWS_AFFECTED);

EXCEPTION
    WHEN OTHER THEN
        IF (UPPER(V_TARGET_TABLE) <> UPPER(P_AUDIT_TABLE_FQN)) THEN
            EXECUTE IMMEDIATE
                'INSERT INTO ' || P_AUDIT_TABLE_FQN || ' (procedure_name, target_table, start_ts, end_ts, status, error_message) VALUES (?, ?, ?, ?, ?, ?)'
                USING (V_PROC_NAME, V_TARGET_TABLE, V_START_TS, CURRENT_TIMESTAMP(), 'FAILED', SQLERRM);
        END IF;
        RETURN OBJECT_CONSTRUCT('status','FAILED','error',SQLERRM);
END;
$$;
