
_____________________________________________

## *Author*: AAVA

## *Created on*: 

## *Description*: Review and validation of Snowflake stored procedure `gold.sp_load_fact_flight_operations` against available inputs for Snowflake compatibility, join integrity, standards, and transformation logic.

## *Version*: 1

## *Updated on*: 

_____________________________________________

### Workflow Summary
The input stored procedure `gold.sp_load_fact_flight_operations` (LANGUAGE SQL, EXECUTE AS OWNER) loads `GOLD.FACT_FLIGHT_OPERATIONS` from `SILVER.SLV_FLIGHT_OPERATIONS` using a DQ gate (`DQ_VALID_FLAG`), de-duplication by `FLIGHT_ID` (latest `UPDATED_TS`), surrogate key lookups to several GOLD dimensions, and a `MERGE` (match on `SCHEDULE_ID` + `DATE_KEY`). It writes pre/post audit records into a caller-provided audit table and returns a VARIANT status object.

---

## 1) Validation Against Metadata
> Mapping/metadata file(s) were not provided in the inputs read from GitHub; validations requiring mapping are marked ❌.

| Item | Status | Details |
|---|---|---|
| Mapping file present (source-to-target rules, column mappings) | ❌ | No mapping/metadata file was found/read in the provided input set; cannot confirm column-level mapping rules. |
| Source table identification (Silver) | ✅ | Uses `IDENTIFIER(P_SOURCE_SCHEMA || '.SLV_FLIGHT_OPERATIONS')`. |
| Target table identification (Gold fact) | ✅ | Uses `IDENTIFIER(P_TARGET_SCHEMA || '.FACT_FLIGHT_OPERATIONS')`. |
| Target columns align to mapping rules | ❌ | Mapping not available; cannot verify completeness/accuracy of column list and required transformations. |
| Data type consistency (source→target, join keys) | ❌ | Without DDLs/mapping, cannot confirm data types for joins/merge keys and insert/update columns. |
| Audit table schema/columns match procedure inserts | ❌ | `P_AUDIT_TABLE_FQN` structure not provided; procedure assumes columns: `procedure_name, target_table, start_ts, end_ts, status, rows_affected, error_message`. |

---

## 2) Compatibility with Snowflake

| Item | Status | Details |
|---|---|---|
| `CREATE OR REPLACE PROCEDURE` syntax valid | ✅ | Uses Snowflake SQL Scripting syntax with `LANGUAGE SQL`. |
| Parameter definitions valid | ✅ | `STRING` parameters with defaults for schemas are valid. |
| Return type valid | ✅ | `RETURNS VARIANT` and returns `OBJECT_CONSTRUCT(...)`. |
| Execution rights specified | ✅ | `EXECUTE AS OWNER` is valid; ensure ownership/privileges align with governance requirements. |
| Variable declaration/assignment valid | ✅ | Uses `DECLARE` and `:=` assignment; supported in SQL scripting. |
| Dynamic SQL usage (`EXECUTE IMMEDIATE ... USING`) valid | ✅ | Correct pattern for binding values into an INSERT statement. |
| Use of `IDENTIFIER()` for dynamic object references | ✅ | Correct for schema/table resolution from parameters. |
| `MERGE` statement structure valid | ✅ | Standard Snowflake MERGE with `WHEN MATCHED` and `WHEN NOT MATCHED`. |
| `RESULT_SCAN(LAST_QUERY_ID())` usage for affected rows | ✅ | Valid approach; note: behavior depends on last statement producing `rows_affected` metadata (MERGE does). |
| Exception handling syntax valid | ✅ | `EXCEPTION WHEN OTHER THEN ... SQLERRM` supported in Snowflake SQL procedures. |
| Transaction handling explicitly controlled | ❌ | No explicit `BEGIN TRANSACTION/COMMIT/ROLLBACK`. Snowflake procedures run in a transaction scope; consider explicit control if audit logging must persist on failure (currently failure insert is attempted, but may rollback depending on session/transaction semantics). |
| Use of unsupported/deprecated features | ✅ | No obvious unsupported constructs; all functions appear Snowflake-supported. |

---

## 3) Validation of Join Operations

| Item | Status | Details |
|---|---|---|
| Join columns exist in joined dimension tables | ❌ | Dimension table DDLs not provided; cannot confirm existence of `DIM_DATE.DATE`, `DIM_AIRLINE.AIRLINE_CODE`, `DIM_AIRPORT.AIRPORT_CODE`, `DIM_AIRCRAFT.TAIL_NUMBER`, `EFFECTIVE_START_DATE`, `EFFECTIVE_END_DATE`. |
| Join data type compatibility | ❌ | Data types not available; cannot validate comparisons (e.g., `dd.DATE = d.FLIGHT_DATE` and date range between `d.FLIGHT_DATE` and aircraft effective dates). |
| DIM_DATE join logic | ✅ | `LEFT JOIN ... ON dd.DATE = d.FLIGHT_DATE` is logically typical if `dd.DATE` is a DATE and `d.FLIGHT_DATE` is DATE. |
| DIM_AIRLINE join logic | ✅ | `da.AIRLINE_CODE = d.CARRIER_CODE` is typical natural key lookup. |
| DIM_AIRPORT joins (origin/destination) | ✅ | Looks up airport keys by `AIRPORT_CODE` for both origin and destination. |
| DIM_AIRCRAFT SCD range join logic | ✅ | Uses tail number plus effective date range; includes open-ended end date via `COALESCE(...,'9999-12-31')`. |
| DIM_ROUTE join implemented per intended relationship | ❌ | Route join is explicitly disabled: `LEFT JOIN ... DIM_ROUTE dr ON 1=0` and comment indicates missing natural key in DIM_ROUTE. This causes `ROUTE_KEY` to be NULL for all rows. |
| Join cardinality/duplication risk controlled | ⚠️ | De-dupe is by `FLIGHT_ID` only; dimension lookups could multiply rows if dimension natural keys are non-unique (cannot confirm without constraints). Also MERGE match key is `SCHEDULE_ID` + `DATE_KEY`, which may not be unique in source. |

---

## 4) Syntax and Code Review

| Item | Status | Details |
|---|---|---|
| SQL syntax appears correct | ✅ | No obvious syntax errors in procedure body. |
| Object naming conventions | ⚠️ | Procedure name `gold.sp_load_fact_flight_operations` is clear; if enterprise standard is `SP_<DOMAIN>_<ACTION>`, this deviates (schema-qualified naming may be acceptable). |
| Consistent casing/formatting | ✅ | Generally consistent and readable. |
| Avoids `SELECT *` in final projection | ✅ | Explicit column lists in SELECT/INSERT/UPDATE. |
| Merge match condition appropriate | ❌ | Matches on `tgt.SCHEDULE_ID` and `tgt.DATE_KEY`. Source de-dup is by `FLIGHT_ID`; if multiple flights share schedule/date, MERGE could update multiple target rows unexpectedly or error with duplicate matches. |
| Null-handling for surrogate keys | ⚠️ | LEFT JOINs can yield NULL keys; whether fact table allows NULL foreign keys is unknown. No default/unknown key handling implemented. |

---

## 5) Compliance with Development Standards

| Item | Status | Details |
|---|---|---|
| Modular design / clear step separation | ✅ | DQ gate, de-dupe, lookups, merge, audit are clearly separated. |
| Logging/auditing implemented | ✅ | Writes RUNNING/SUCCESS/FAILED rows into an audit table and returns status object. |
| Audit inserts protected against recursion | ✅ | Guard `IF (UPPER(V_TARGET_TABLE) <> UPPER(P_AUDIT_TABLE_FQN))`. |
| Audit robustness under failure | ❌ | Audit writes occur in same transaction context; on exception, the FAILED insert may rollback with the MERGE depending on transaction behavior. Consider autonomous logging pattern (Snowflake lacks true autonomous transactions; use separate logging mechanism like external function/event table pattern or commit strategy). |
| Idempotency/re-runnability | ⚠️ | MERGE supports re-runs, but match keys may not guarantee deterministic updates if not unique. |
| Parameter validation (non-null/empty checks) | ❌ | No validation that `P_AUDIT_TABLE_FQN` exists/is accessible or that schemas are valid. |

---

## 6) Validation of Transformation Logic

| Item | Status | Details |
|---|---|---|
| DQ filtering logic correct | ✅ | Explicitly blocks run if any invalid rows exist; also filters to valid rows in load query. |
| De-duplication logic correct | ⚠️ | `ROW_NUMBER() ... PARTITION BY FLIGHT_ID ORDER BY UPDATED_TS DESC` assumes `UPDATED_TS` is populated and comparable; ties not broken deterministically. |
| Surrogate key lookup logic | ⚠️ | Standard lookups, but no handling of missing dimension matches (unknown members). |
| Route key derivation | ❌ | `ROUTE_KEY` will always be NULL due to `ON 1=0`. |
| Fact grain consistency | ❌ | Source de-dupe grain (FLIGHT_ID) differs from MERGE key grain (SCHEDULE_ID, DATE_KEY). This can create incorrect updates/inserts or duplicates. |
| DW audit timestamps | ✅ | Sets `DW_CREATED_TS`/`DW_UPDATED_TS` on insert; updates `DW_UPDATED_TS` on update. |

---

## 7) Error Reporting and Recommendations

| Finding (❌ / ⚠️) | Impact | Recommendation |
|---|---|---|
| ❌ Mapping/metadata file not found | Cannot validate column mappings, data types, required transformations, or mandatory fields | Add/read the mapping/metadata artifact(s) (e.g., source/target DDLs and column mapping sheet) in the input directory; re-run review. |
| ❌ Audit table schema unknown | Possible runtime failure if audit table columns differ | Provide DDL for audit table; or change procedure to accept a structured logging interface (fixed table) and validate existence via `INFORMATION_SCHEMA.COLUMNS`. |
| ❌ DIM_ROUTE join disabled (`ON 1=0`) | ROUTE_KEY always NULL; breaks referential integrity and downstream analytics | Fix DIM_ROUTE to include a natural key (e.g., `ROUTE_ID` or `ROUTE_CODE`) and implement `ON dr.<natural_key> = d.ROUTE_ID` (or via a bridge from Silver route table). If not possible, document and load an `UNKNOWN` route key via default surrogate key. |
| ❌ MERGE key mismatch vs de-dupe grain | Risk of incorrect updates, duplicate rows, or MERGE error due to multiple matches | Align MERGE ON clause with the fact grain (likely `FLIGHT_ID`), or de-dupe and load at the same grain as MERGE key. Add a uniqueness assertion on source keys prior to MERGE. |
| ❌ Transaction/audit durability not guaranteed | Failure logging may rollback, losing audit trail | Consider committing audit RUNNING row before MERGE (if policy allows), or write audit to a separate mechanism (e.g., Snowflake event table with `SYSTEM$LOG`, or externalized logging). At minimum, document transaction behavior and test. |
| ❌ No parameter validation | Runtime failures due to invalid schema/table names or missing privileges | Add checks: `SHOW TABLES LIKE ...`, query `INFORMATION_SCHEMA.TABLES/COLUMNS`, and raise a controlled error with actionable message when missing. |
| ⚠️ Non-deterministic de-dupe ties | Potential inconsistent results if same `UPDATED_TS` | Extend ORDER BY (e.g., `UPDATED_TS DESC, CREATED_TS DESC, FLIGHT_ID`) or include ingestion timestamp/sequence. |
| ⚠️ Missing unknown-dimension handling | NULL foreign keys may violate target constraints/analytics expectations | Standardize on `-1` (UNKNOWN) surrogate keys in dimensions and use `COALESCE(dim_key, -1)` in fact load. |
| ⚠️ Dimension uniqueness not enforced | Possible row multiplication | Ensure dimension natural keys are unique (constraints or data quality checks) and/or qualify latest row for SCD dimensions. |

