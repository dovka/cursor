# Aurora Postgres to Redshift View Conversion Summary

## Conversion Status: ✅ POSSIBLE

The view can be converted to Redshift with the following changes and assumptions.

---

## ASSUMPTIONS REQUIRING CONFIRMATION

### 1. **Table Name Pattern**
- **Assumption**: Using the same table naming pattern as the MV_RUNS_DP_KM example
- **Pattern**: `datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_<table_name>`
- **Tables used**:
  - `nimbus_runs`
  - `nimbus_steps`
  - `failure_reasons`
  - `run_to_step_association`

### 2. **Time Filter**
- **Original**: `WHERE time_created >= (now() - '70 days'::interval)`
- **Converted**: `WHERE time_created >= DATEADD(day, -70, GETDATE())`
- **Question**: Should this remain at 70 days or change to match table example (6 months)?

### 3. **JSON Field Data Types**
The original view extracts these statistics fields as TEXT (VARCHAR):
- `fractional_factor`
- `exec_cpu_hours`
- `executor_cores`
- `driver_cpu_hours`
- `app_required_cores`
- `step_app_duration_in_minutes`

**Note**: The MV_RUNS_DP_KM table example casts these to numeric types (float/int) with NULLIF handling for 'NaN' and empty strings.

**Options**:
- **A) Keep as VARCHAR** (matches original view exactly) - **CURRENT APPROACH**
- **B) Cast to numeric types** (matches table example, better for calculations)

### 4. **Date/Timestamp Fields**
- **Original view**: Returns full timestamps
- **Table example**: Casts to date only (loses time component)
- **Current approach**: Keeps as timestamps to match original view exactly

### 5. **Schema and Ownership**
- **Schema**: `public`
- **Grants**: Using roles from example:
  - `"IAMR:cu-rem-pm-users"`
  - `quicksight_user`
- **Question**: Are these the correct roles for your environment?

---

## KEY TECHNICAL CHANGES (Required for Redshift)

### 1. **Late Binding View** (CRITICAL)
Added `WITH NO SCHEMA BINDING` to CREATE VIEW statement.

**Required because**: Redshift doesn't allow views to reference external Glue catalog tables without late binding.

**Error without it**:
```
ERROR: External tables are not supported in views
Hint: Please use late binding view and add 'with no schema binding' at the query end.
```

**Impact**: The view becomes a "late binding view" which validates schema at query time, not creation time.

### 2. **JSON Extraction Syntax**
| Postgres | Redshift |
|----------|----------|
| `metadata_json -> 'key'` | `JSON_EXTRACT_PATH_TEXT(metadata_json, 'key', true)` |
| `metadata_json ->> 'key'` | `JSON_EXTRACT_PATH_TEXT(metadata_json, 'key', true)` |
| `metadata_json -> 'key1' ->> 'key2'` | `JSON_EXTRACT_PATH_TEXT(metadata_json, 'key1', 'key2', true)` |

### 3. **Window Function Frame**
| Postgres | Redshift |
|----------|----------|
| `RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` | `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` |

**Reason**: Redshift doesn't support RANGE in window functions

### 4. **Added JSON Validation**
Added to nimbus_steps CTE WHERE clause:
```sql
AND nimbus_steps.metadata_json IS NOT NULL 
AND IS_VALID_JSON(nimbus_steps.metadata_json)
```

This prevents JSON parsing errors (following the table example pattern).

---

## FIELD COMPARISON

### Total Fields: **52** (all preserved)

All 52 fields from the original Postgres view are present in the Redshift view with matching names and order.

**Additional fields in VIEW vs the MV_RUNS_DP_KM TABLE**:
The view includes these fields that were NOT in the table example:
1. `run_id` (integer)
2. `step_id` (integer)
3. `step_failure_reason` (raw failure_reason value)
4. `step_number_of_cores`
5. `step_original_run_id`
6. `step_cloud_region`
7. `remcmcellsize`
8. `remprocessmapsize`
9. `clustername`

These are all present in the Redshift view conversion.

---

## COMPATIBILITY NOTES

### ✅ What Works Identically
- All column names and order preserved
- All joins and CTEs structure preserved
- LEFT JOIN and INNER JOIN logic preserved
- LAST_VALUE window function preserved (with RANGE→ROWS change)

### ⚠️ Potential Differences
1. **JSON extraction with invalid JSON**: Redshift may return NULL where Postgres might error
2. **Window function behavior**: ROWS vs RANGE may produce different results if there are duplicate timestamps (unlikely with tie-breaking on other columns)
3. **Date arithmetic precision**: DATEADD(day, -70, GETDATE()) vs `now() - '70 days'::interval` should be equivalent but may differ by milliseconds

---

## RECOMMENDATIONS

### Option 1: Exact Field Type Match (Current)
Keep all extracted JSON fields as VARCHAR to exactly match the original view structure.

**Pros**: Exact match to original view  
**Cons**: Requires casting for numeric operations in queries

### Option 2: Optimize for Redshift (Alternative)
Cast statistics fields to numeric types with NULLIF handling (like the table example).

**Pros**: Better query performance, handles 'NaN' values  
**Cons**: Different data types than original view

---

## NEXT STEPS - CONFIRMATIONS NEEDED

Please confirm the following assumptions:

### ❓ 1. Table Naming Pattern
**Assumption**: Using pattern from MV_RUNS_DP_KM example  
**Pattern**: `datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_<table_name>`

**Tables referenced**:
- `...public_nimbus_runs`
- `...public_nimbus_steps`
- `...public_failure_reasons`
- `...public_run_to_step_association`

**Confirm**: Is this naming pattern correct? ☐ YES ☐ NO (provide correct pattern)

---

### ❓ 2. Time Filter Duration
**Original**: `WHERE time_created >= (now() - '70 days'::interval)`  
**Converted**: `WHERE time_created >= DATEADD(day, -70, GETDATE())`

**Confirm**: Keep 70-day filter? ☐ YES ☐ NO (specify: _____ days/months)

---

### ❓ 3. Statistics Fields Data Types
**Fields affected**: 
- fractional_factor
- exec_cpu_hours
- executor_cores
- driver_cpu_hours
- app_required_cores
- step_app_duration_in_minutes

**Option 1**: Keep as VARCHAR (exact match to Postgres view)  
**Option 2**: Cast to FLOAT/INT with NULLIF for NaN handling (matches MV_RUNS_DP_KM table)

**Confirm**: Which option? ☐ OPTION 1 (VARCHAR) ☐ OPTION 2 (NUMERIC)

---

### ❓ 4. Timestamp vs Date Fields
**Original**: All time fields are TIMESTAMP  
**Table example**: Casts to DATE (loses time component)

**Confirm**: Keep as TIMESTAMP? ☐ YES ☐ NO (cast to DATE)

---

### ❓ 5. Grant Roles
**Proposed grants**:
```sql
GRANT SELECT ON public.v_nimbus_runs_dp_km TO "IAMR:cu-rem-pm-users";
GRANT SELECT ON public.v_nimbus_runs_dp_km TO quicksight_user;
```

**Confirm**: Are these roles correct? ☐ YES ☐ NO (provide correct roles: _____________)

---

### ❓ 6. Schema
**Proposed**: `public` schema

**Confirm**: Create in public schema? ☐ YES ☐ NO (specify schema: _____________)

---

## DECISION MATRIX

| Question | Your Answer | SQL File to Use |
|----------|-------------|-----------------|
| Statistics fields as VARCHAR or NUMERIC? | ☐ VARCHAR ☐ NUMERIC | Version 1 / Version 2 |
| Keep timestamps or convert to dates? | ☐ TIMESTAMP ☐ DATE | Modify selected version |
| 70-day filter correct? | ☐ YES ☐ NO (___days) | Modify selected version |
| Table names correct? | ☐ YES ☐ NO | Modify selected version |
| Grant roles correct? | ☐ YES ☐ NO | Modify grants section |
| Schema correct? | ☐ YES ☐ NO | Modify schema name |

---

## FILES GENERATED

1. `v_nimbus_runs_dp_km_redshift.sql` - Main Redshift view creation script (with Option 1: VARCHAR fields)
2. `CONVERSION_SUMMARY.md` - This summary document

