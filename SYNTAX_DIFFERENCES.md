# SQL Syntax Differences: Postgres vs Redshift

This document highlights the key syntax changes required for Redshift compatibility.

---

## 1. JSON Extraction

### Postgres Syntax
```sql
-- Single-level extraction (text)
metadata_json ->> 'cluster_name'

-- Nested extraction (navigate then extract text)
(metadata_json -> 'resources_tags') ->> 'RemCMCellId'

-- Multi-level nested extraction
(metadata_json -> 'statistics') ->> 'exec_cpu_hours'
```

### Redshift Syntax
```sql
-- Single-level extraction (text)
JSON_EXTRACT_PATH_TEXT(metadata_json, 'cluster_name', true)

-- Nested extraction (all in one function)
JSON_EXTRACT_PATH_TEXT(metadata_json, 'resources_tags', 'RemCMCellId', true)

-- Multi-level nested extraction
JSON_EXTRACT_PATH_TEXT(metadata_json, 'statistics', 'exec_cpu_hours', true)
```

**Note**: The `true` parameter in Redshift's `JSON_EXTRACT_PATH_TEXT()` means case-sensitive key matching.

---

## 2. Date/Time Arithmetic

### Postgres Syntax
```sql
-- Subtract interval from current time
WHERE time_created >= (now() - '70 days'::interval)
```

### Redshift Syntax
```sql
-- Use DATEADD function
WHERE time_created >= DATEADD(day, -70, GETDATE())
```

**Alternative Redshift syntax** (also valid):
```sql
WHERE time_created >= GETDATE() - 70
```

---

## 3. Window Functions - Frame Specification

### Postgres Syntax
```sql
LAST_VALUE(nr.status) OVER (
    PARTITION BY ns.remcmcellid 
    ORDER BY nr.time_created 
    RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
```

### Redshift Syntax
```sql
LAST_VALUE(nr.status) OVER (
    PARTITION BY ns.remcmcellid 
    ORDER BY nr.time_created 
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
```

**Why**: Redshift doesn't support `RANGE` frame specification in window functions. Use `ROWS` instead.

**Impact**: Minimal - for this use case, `ROWS` and `RANGE` produce identical results because we're using `UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`.

---

## 4. JSON Validation

### Postgres
No explicit validation in the original view (Postgres handles invalid JSON more gracefully).

### Redshift (Added)
```sql
WHERE metadata_json IS NOT NULL 
  AND IS_VALID_JSON(metadata_json)
```

**Why**: Redshift requires explicit JSON validation to prevent errors during JSON extraction.

---

## 5. Handling Invalid Numeric Values in JSON (Optional Enhancement)

### Original Postgres
```sql
-- Returns text as-is
metadata_json ->> 'fractional_factor' AS fractional_factor
```

### Redshift Version 1 (Exact Match)
```sql
-- Returns text as-is
JSON_EXTRACT_PATH_TEXT(metadata_json, 'fractional_factor', true) AS fractional_factor
```

### Redshift Version 2 (Enhanced)
```sql
-- Converts to numeric, handling NaN and empty strings
NULLIF(NULLIF(JSON_EXTRACT_PATH_TEXT(metadata_json, 'fractional_factor', true), 'NaN'), '')::float AS fractional_factor
```

**Breakdown**:
- Inner `NULLIF(..., 'NaN')`: Convert 'NaN' string to NULL
- Outer `NULLIF(..., '')`: Convert empty strings to NULL  
- `::float`: Cast to float type

---

## 6. Table Name Patterns

### Postgres (Aurora)
```sql
FROM nimbus_runs
LEFT JOIN failure_reasons ON ...
```

### Redshift (with Glue Catalog)
```sql
FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_nimbus_runs nimbus_runs
LEFT JOIN datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_failure_reasons failure_reasons ON ...
```

**Pattern**: `{catalog}.{database}__{schema}_{table_name}`

---

## 7. Quoted Identifiers

### Both Postgres and Redshift
```sql
-- Preserve case-sensitive column name
AS "user"
```

**Note**: Column name "user" must be quoted because it's a reserved keyword. This syntax is identical in both databases.

---

## 8. Late Binding Views (Critical for External Tables)

### Postgres
```sql
CREATE OR REPLACE VIEW public.v_nimbus_runs_dp_km
AS
SELECT ...
```

### Redshift (with Glue Catalog External Tables)
```sql
CREATE OR REPLACE VIEW public.v_nimbus_runs_dp_km AS
SELECT ...
WITH NO SCHEMA BINDING;
```

**Note**: `WITH NO SCHEMA BINDING` goes at the **end** of the CREATE VIEW statement, not after the view name.

**Why**: Redshift requires `WITH NO SCHEMA BINDING` (late binding) for views that reference external tables in Glue catalog. Without this, you'll get:
```
ERROR: External tables are not supported in views
Hint: Please use late binding view and add 'with no schema binding' at the query end.
```

**Important**: Late binding views:
- Don't validate column names/types at creation time
- Validate at query execution time
- Required for external tables
- Allow schema changes in source tables without recreating view

---

## 9. Data Type Casting

### Postgres
```sql
-- Postgres interval syntax
'70 days'::interval

-- Text to numeric
some_field::float
```

### Redshift
```sql
-- Redshift uses DATEADD instead
DATEADD(day, -70, GETDATE())

-- Text to numeric (same as Postgres)
some_field::float
```

---

## Complete Example: Before and After

### Postgres Original
```sql
ns AS (
    SELECT
        nimbus_steps.id,
        (nimbus_steps.metadata_json -> 'resources_tags') ->> 'RemCMCellId' AS remcmcellid,
        (nimbus_steps.metadata_json -> 'statistics') ->> 'exec_cpu_hours' AS exec_cpu_hours
    FROM nimbus_steps
    LEFT JOIN failure_reasons ON failure_reasons.value = nimbus_steps.failure_reason
    WHERE nimbus_steps.time_created >= (now() - '70 days'::interval)
)
```

### Redshift Converted (Version 1)
```sql
ns AS (
    SELECT
        nimbus_steps.id,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'RemCMCellId', true) AS remcmcellid,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'statistics', 'exec_cpu_hours', true) AS exec_cpu_hours
    FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_nimbus_steps nimbus_steps
    LEFT JOIN datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_failure_reasons failure_reasons 
        ON failure_reasons.value = nimbus_steps.failure_reason
    WHERE nimbus_steps.time_created >= DATEADD(day, -70, GETDATE())
        AND nimbus_steps.metadata_json IS NOT NULL 
        AND IS_VALID_JSON(nimbus_steps.metadata_json)
)
```

### Redshift Converted (Version 2 - with numeric casting)
```sql
ns AS (
    SELECT
        nimbus_steps.id,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'RemCMCellId', true) AS remcmcellid,
        NULLIF(NULLIF(JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'statistics', 'exec_cpu_hours', true), 'NaN'), '')::float AS exec_cpu_hours
    FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_nimbus_steps nimbus_steps
    LEFT JOIN datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_failure_reasons failure_reasons 
        ON failure_reasons.value = nimbus_steps.failure_reason
    WHERE nimbus_steps.time_created >= DATEADD(day, -70, GETDATE())
        AND nimbus_steps.metadata_json IS NOT NULL 
        AND IS_VALID_JSON(nimbus_steps.metadata_json)
)
```

---

## Summary of Changes

| Feature | Postgres | Redshift | Breaking? |
|---------|----------|----------|-----------|
| View binding | Default | `WITH NO SCHEMA BINDING` (required) | ✅ Yes |
| JSON extraction | `->` and `->>` | `JSON_EXTRACT_PATH_TEXT()` | ✅ Yes |
| Date arithmetic | `interval` | `DATEADD()` | ✅ Yes |
| Window frames | `RANGE` | `ROWS` | ✅ Yes |
| JSON validation | Implicit | Explicit with `IS_VALID_JSON()` | ⚠️ Recommended |
| Table names | Simple names | Full catalog paths | ✅ Yes |
| Numeric casting | Optional | Same (Version 2 adds NULLIF) | ⚠️ Optional |

---

## Testing Queries

### Test JSON Extraction
```sql
-- Run in Redshift
SELECT 
    JSON_EXTRACT_PATH_TEXT('{"resources_tags": {"RemCMCellId": "12345"}}', 'resources_tags', 'RemCMCellId', true) as test;
-- Expected: '12345'
```

### Test Date Arithmetic
```sql
-- Run in Redshift
SELECT DATEADD(day, -70, GETDATE()) as cutoff_date;
-- Expected: Date 70 days ago
```

### Test Numeric Casting with NULLIF
```sql
-- Run in Redshift
SELECT 
    NULLIF(NULLIF('123.45', 'NaN'), '')::float as valid_number,
    NULLIF(NULLIF('NaN', 'NaN'), '')::float as nan_value,
    NULLIF(NULLIF('', 'NaN'), '')::float as empty_value;
-- Expected: 123.45, NULL, NULL
```
