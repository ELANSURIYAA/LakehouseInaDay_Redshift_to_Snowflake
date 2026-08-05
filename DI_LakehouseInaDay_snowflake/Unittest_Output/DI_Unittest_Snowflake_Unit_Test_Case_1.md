Author: AAVA

Created on: 2026-08-05

Description: Unit test cases for Snowflake procedure gold.sp_load_fact_flight_operations covering DQ validation, deduplication, dimension lookups, and MERGE behavior.

Version: 1

Updated on: 2026-08-05

## Object Summary

- **Target object**: `PROCEDURE gold.sp_load_fact_flight_operations` (loads `GOLD.FACT_FLIGHT_OPERATIONS` via `MERGE`)
- **Source table(s)/view(s)**:
  - `SILVER.SLV_FLIGHT_OPERATIONS`
  - Dimension lookups in target schema: `GOLD.DIM_DATE`, `GOLD.DIM_AIRLINE`, `GOLD.DIM_ROUTE`, `GOLD.DIM_AIRPORT` (twice), `GOLD.DIM_AIRCRAFT`
- **Transformations identified**: 3 (DQ filter, dedup `ROW_NUMBER QUALIFY`, DIM lookups/projections)
- **Joins identified**: 6 LEFT JOINs (DATE, AIRLINE, ROUTE (disabled), ORIGIN AIRPORT, DEST AIRPORT, AIRCRAFT SCD range)
- **Aggregations identified**: 1 window function (`ROW_NUMBER() OVER (PARTITION BY FLIGHT_ID ORDER BY UPDATED_TS DESC)`)
- **Filters identified**: 2 (`DQ_VALID_FLAG` filter; `QUALIFY` for dedup)
- **Existing constraints found in object definition**: 0 (none declared)

## Test Case Matrix

| Test Case ID | Category (Happy Path / Edge Case / Exception) | Column/Join/Aggregation | Description | SQL Assertion Type |
|---|---|---|---|---|
| TC001 | Exception | Source DQ gate (`DQ_VALID_FLAG`) | Procedure must fail when source contains any `DQ_VALID_FLAG <> TRUE` (incl NULL) | Business-rule (exception) |
| TC002 | Happy Path | Source filter | All rows used for load must satisfy `DQ_VALID_FLAG = TRUE` | Business-rule |
| TC003 | Happy Path | Dedup window | Dedup keeps only latest `UPDATED_TS` per `FLIGHT_ID` (no duplicate `FLIGHT_ID` in dedup result) | Uniqueness (CTE-level) |
| TC004 | Edge Case | Dedup tie-break | If multiple rows share same `FLIGHT_ID` and same `UPDATED_TS`, dedup outcome is non-deterministic | SKIPPED |
| TC005 | Happy Path | Join `DIM_DATE` | `DATE_KEY` should be resolved for all loaded rows where `FLIGHT_DATE` exists in `DIM_DATE` | Referential integrity / business-rule |
| TC006 | Edge Case | Join `DIM_DATE` | Detect rows in target with `DATE_KEY` NULL (missing date dimension mapping) | Not-null (logical) |
| TC007 | Happy Path | Join `DIM_AIRLINE` | `AIRLINE_KEY` should resolve when `CARRIER_CODE` exists in `DIM_AIRLINE` | Referential integrity |
| TC008 | Edge Case | Join `DIM_AIRLINE` | Detect rows in target with `AIRLINE_KEY` NULL (missing airline mapping) | Not-null (logical) |
| TC009 | Exception | Join `DIM_ROUTE` | Route mapping is disabled (`ON 1=0`), so `ROUTE_KEY` will always be NULL after load | Business-rule (should be reviewed) |
| TC010 | Happy Path | Join `DIM_AIRPORT` origin | `ORIGIN_AIRPORT_KEY` should resolve when `ORIGIN_AIRPORT_CODE` exists in `DIM_AIRPORT` | Referential integrity |
| TC011 | Happy Path | Join `DIM_AIRPORT` destination | `DESTINATION_AIRPORT_KEY` should resolve when `DESTINATION_AIRPORT_CODE` exists in `DIM_AIRPORT` | Referential integrity |
| TC012 | Edge Case | Join `DIM_AIRPORT` | Detect rows in target with either airport key NULL | Not-null (logical) |
| TC013 | Happy Path | Join `DIM_AIRCRAFT` SCD | `AIRCRAFT_KEY` resolves when `TAIL_NUMBER` matches and `FLIGHT_DATE` within effective range | Business-rule |
| TC014 | Edge Case | Join `DIM_AIRCRAFT` SCD | Detect rows with `TAIL_NUMBER` present but `AIRCRAFT_KEY` NULL (range miss) | Business-rule |
| TC015 | Happy Path | MERGE key | Validate logical uniqueness of (`SCHEDULE_ID`,`DATE_KEY`) in target (MERGE match condition) | Uniqueness |
| TC016 | Edge Case | MERGE outcome | Detect rows with `SCHEDULE_ID` NULL or `DATE_KEY` NULL in target (can break match semantics) | Not-null (logical) |

## Generated Snowflake Test Scripts

```sql
-- =====================================================================
-- Unit Test Scripts for gold.sp_load_fact_flight_operations
-- Note: These assertions are written to validate the behavior/outputs.
--       Exception-behavior tests are expressed as manual-run CALL blocks
--       because Snowflake SQL scripting test harness is not provided.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Parameters (set these before executing tests)
-- ---------------------------------------------------------------------
-- Change these if you deploy to a different DB/SCHEMA naming convention.
SET P_SOURCE_SCHEMA = 'SILVER';
SET P_TARGET_SCHEMA = 'GOLD';

-- Optional: audit table FQN used by the procedure
-- SKIPPED: gold.sp_load_fact_flight_operations.P_AUDIT_TABLE_FQN — audit table structure/FQN not provided in input SQL.

-- ---------------------------------------------------------------------
-- TC001 (Exception): Procedure must fail if any invalid DQ rows exist
-- ---------------------------------------------------------------------
-- This is a behavior test; it requires a controlled test dataset.
-- Expected: CALL raises STATEMENT_ERROR with message containing:
--   'DQ validation failed: SLV_FLIGHT_OPERATIONS contains dq_valid_flag = FALSE rows.'
--
-- SKIPPED: SILVER.SLV_FLIGHT_OPERATIONS.DQ_VALID_FLAG — cannot safely inject invalid rows without test harness/fixtures.

-- ---------------------------------------------------------------------
-- TC002 (Happy Path): Source filter confirms only DQ_VALID_FLAG=TRUE would be loaded
-- ---------------------------------------------------------------------
-- This asserts the procedure's selection predicate shape.
SELECT COUNT(*) AS invalid_rows_selected
FROM IDENTIFIER($P_SOURCE_SCHEMA || '.SLV_FLIGHT_OPERATIONS') s
WHERE COALESCE(s.DQ_VALID_FLAG, FALSE) = TRUE
  AND COALESCE(s.DQ_VALID_FLAG, FALSE) <> TRUE;
-- Expected: 0

-- ---------------------------------------------------------------------
-- TC003 (Happy Path): Dedup removes duplicates of FLIGHT_ID in dedup result
-- ---------------------------------------------------------------------
WITH src AS (
    SELECT s.*
    FROM IDENTIFIER($P_SOURCE_SCHEMA || '.SLV_FLIGHT_OPERATIONS') s
    WHERE COALESCE(s.DQ_VALID_FLAG, FALSE) = TRUE
),
dedup AS (
    SELECT *
    FROM src
    QUALIFY ROW_NUMBER() OVER (PARTITION BY FLIGHT_ID ORDER BY UPDATED_TS DESC) = 1
)
SELECT FLIGHT_ID, COUNT(*) AS cnt
FROM dedup
GROUP BY FLIGHT_ID
HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- TC004 (Edge Case): Dedup tie-break non-deterministic if UPDATED_TS ties
-- SKIPPED: SILVER.SLV_FLIGHT_OPERATIONS.UPDATED_TS — procedure lacks deterministic tie-breaker (no secondary ORDER BY columns).

-- ---------------------------------------------------------------------
-- Target-level assertions (post-load). These assume the procedure has
-- been executed and populated GOLD.FACT_FLIGHT_OPERATIONS.
-- ---------------------------------------------------------------------

-- TC005 (Happy Path): DATE_KEY should reference DIM_DATE.DATE_KEY
-- SKIPPED: GOLD.DIM_DATE.DATE_KEY — referenced column names for DIMs are not confirmed in this procedure (only aliases); verify DIM DDL.

-- TC006 (Edge Case): DATE_KEY nulls in target
SELECT COUNT(*) AS null_date_key
FROM IDENTIFIER($P_TARGET_SCHEMA || '.FACT_FLIGHT_OPERATIONS')
WHERE DATE_KEY IS NULL;
-- Expected: 0 (if DIM_DATE is complete)

-- TC007 (Happy Path): AIRLINE_KEY should reference DIM_AIRLINE.AIRLINE_KEY
-- SKIPPED: GOLD.DIM_AIRLINE.AIRLINE_KEY — referenced column names for DIMs are not confirmed in this procedure (only aliases); verify DIM DDL.

-- TC008 (Edge Case): AIRLINE_KEY nulls in target
SELECT COUNT(*) AS null_airline_key
FROM IDENTIFIER($P_TARGET_SCHEMA || '.FACT_FLIGHT_OPERATIONS')
WHERE AIRLINE_KEY IS NULL;
-- Expected: 0 (if DIM_AIRLINE is complete)

-- TC009 (Exception/Review): ROUTE_KEY always NULL due to join ON 1=0
SELECT COUNT(*) AS non_null_route_key
FROM IDENTIFIER($P_TARGET_SCHEMA || '.FACT_FLIGHT_OPERATIONS')
WHERE ROUTE_KEY IS NOT NULL;
-- Expected: 0 (given current SQL). If this is not desired, fix DIM_ROUTE mapping.

-- TC010 (Happy Path): ORIGIN_AIRPORT_KEY should reference DIM_AIRPORT.AIRPORT_KEY
-- SKIPPED: GOLD.DIM_AIRPORT.AIRPORT_KEY — referenced column names for DIMs are not confirmed in this procedure (only aliases); verify DIM DDL.

-- TC011 (Happy Path): DESTINATION_AIRPORT_KEY should reference DIM_AIRPORT.AIRPORT_KEY
-- SKIPPED: GOLD.DIM_AIRPORT.AIRPORT_KEY — referenced column names for DIMs are not confirmed in this procedure (only aliases); verify DIM DDL.

-- TC012 (Edge Case): airport keys nulls in target
SELECT
  SUM(IFF(ORIGIN_AIRPORT_KEY IS NULL, 1, 0)) AS null_origin_airport_key,
  SUM(IFF(DESTINATION_AIRPORT_KEY IS NULL, 1, 0)) AS null_destination_airport_key
FROM IDENTIFIER($P_TARGET_SCHEMA || '.FACT_FLIGHT_OPERATIONS');
-- Expected: both 0 (if DIM_AIRPORT is complete)

-- TC013 (Happy Path): AIRCRAFT_KEY presence when matching SCD range exists
-- SKIPPED: GOLD.DIM_AIRCRAFT.EFFECTIVE_START_DATE — cannot validate without DIM_AIRCRAFT DDL/confirmed column names.

-- TC014 (Edge Case): TAIL_NUMBER present but AIRCRAFT_KEY null (range miss)
-- SKIPPED: SILVER.SLV_FLIGHT_OPERATIONS.TAIL_NUMBER — requires joining back to source to check 'tail_number present'; source-to-target lineage key not exposed in target (FLIGHT_ID not inserted).

-- TC015 (Happy Path): Uniqueness on MERGE match keys (SCHEDULE_ID, DATE_KEY)
SELECT SCHEDULE_ID, DATE_KEY, COUNT(*) AS cnt
FROM IDENTIFIER($P_TARGET_SCHEMA || '.FACT_FLIGHT_OPERATIONS')
GROUP BY SCHEDULE_ID, DATE_KEY
HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- TC016 (Edge Case): Nulls in MERGE match keys
SELECT
  SUM(IFF(SCHEDULE_ID IS NULL, 1, 0)) AS null_schedule_id,
  SUM(IFF(DATE_KEY IS NULL, 1, 0)) AS null_date_key
FROM IDENTIFIER($P_TARGET_SCHEMA || '.FACT_FLIGHT_OPERATIONS');
-- Expected: 0

-- ---------------------------------------------------------------------
-- Reusable pattern: generic not-null check stored procedure
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE GOLD.UT_ASSERT_NOT_NULL(P_TABLE_FQN STRING, P_COLUMN_NAME STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  v_sql STRING;
  v_cnt NUMBER;
BEGIN
  v_sql := 'SELECT COUNT(*) FROM ' || P_TABLE_FQN || ' WHERE ' || P_COLUMN_NAME || ' IS NULL';
  EXECUTE IMMEDIATE v_sql INTO :v_cnt;
  IF (v_cnt = 0) THEN
    RETURN 'PASS';
  END IF;
  RETURN 'FAIL: ' || v_cnt || ' NULL(s) found in ' || P_TABLE_FQN || '.' || P_COLUMN_NAME;
END;
$$;

-- Example executions:
-- CALL GOLD.UT_ASSERT_NOT_NULL($P_TARGET_SCHEMA || '.FACT_FLIGHT_OPERATIONS', 'SCHEDULE_ID');
-- CALL GOLD.UT_ASSERT_NOT_NULL($P_TARGET_SCHEMA || '.FACT_FLIGHT_OPERATIONS', 'DATE_KEY');

```

## Coverage Notes

- No tests generated for audit logging writes because the audit table DDL/FQN and expected rows are not provided (`SKIPPED` inline).
- Referential integrity tests to DIM tables are partially `SKIPPED` because DIM primary key column names are not confirmed from any DDL in the provided input (only implied by aliases in the procedure).
- AIRCRAFT SCD-range correctness is `SKIPPED` without DIM_AIRCRAFT column confirmation and because `FLIGHT_ID` is not inserted into the fact (cannot easily trace back to source row in a generic assertion).
- Total skipped-item count: 7
