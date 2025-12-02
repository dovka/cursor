# Validation Checklist for Redshift View Deployment

Use this checklist to validate the conversion before deploying to production.

## Pre-Deployment Verification

### 1. Assumptions Confirmation
- [ ] **Table names** are correct: `datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_*`
  - [ ] nimbus_runs
  - [ ] nimbus_steps
  - [ ] failure_reasons
  - [ ] run_to_step_association
- [ ] **70-day filter** is correct (or should it be changed?)
- [ ] **Grant roles** are correct:
  - [ ] `"IAMR:cu-rem-pm-users"` exists and is correct
  - [ ] `quicksight_user` exists and is correct
- [ ] **Schema** is `public` (or specify different schema)
- [ ] **Version selected**: Version 1 (VARCHAR) or Version 2 (numeric casting)

### 2. Source Table Validation in Redshift
Run these queries to verify source tables exist and have data:

```sql
-- Check nimbus_runs
SELECT COUNT(*) as count, 
       MIN(time_created) as oldest, 
       MAX(time_created) as newest
FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_nimbus_runs
WHERE time_created >= DATEADD(day, -70, GETDATE());

-- Check nimbus_steps  
SELECT COUNT(*) as count,
       MIN(time_created) as oldest,
       MAX(time_created) as newest,
       SUM(CASE WHEN metadata_json IS NULL THEN 1 ELSE 0 END) as null_json_count,
       SUM(CASE WHEN NOT IS_VALID_JSON(metadata_json) THEN 1 ELSE 0 END) as invalid_json_count
FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_nimbus_steps
WHERE time_created >= DATEADD(day, -70, GETDATE());

-- Check failure_reasons
SELECT COUNT(*) as count FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_failure_reasons;

-- Check run_to_step_association
SELECT COUNT(*) as count FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_run_to_step_association;
```

**Expected Results**:
- [ ] All tables exist and return results without errors
- [ ] Counts are reasonable (not zero unless expected)
- [ ] Date ranges are within expected bounds

### 3. JSON Field Validation
Test JSON extraction on a sample record:

```sql
SELECT 
    id,
    metadata_json,
    JSON_EXTRACT_PATH_TEXT(metadata_json, 'resources_tags', 'RemCMCellId', true) as remcmcellid,
    JSON_EXTRACT_PATH_TEXT(metadata_json, 'statistics', 'exec_cpu_hours', true) as exec_cpu_hours
FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_nimbus_steps
WHERE metadata_json IS NOT NULL 
  AND IS_VALID_JSON(metadata_json)
LIMIT 5;
```

**Expected Results**:
- [ ] JSON extraction returns expected values
- [ ] No errors on extraction
- [ ] Values match expectations from Postgres

### 4. View Creation Test (Dry Run)
Before creating the view, test the SELECT statement:

```sql
-- Copy the entire SELECT statement from the chosen version and run it
-- This validates the query syntax without creating the view
-- Expected: Query completes successfully
```

**Expected Results**:
- [ ] Query runs without errors
- [ ] Returns expected number of rows
- [ ] All columns are present

### 5. Row Count Comparison (After Deployment)
After creating the view, compare row counts:

```sql
-- Redshift view
SELECT COUNT(*) as redshift_count FROM public.v_nimbus_runs_dp_km;

-- If possible, compare with Postgres (run in Postgres)
-- SELECT COUNT(*) as postgres_count FROM public.v_nimbus_runs_dp_km;
```

**Expected Results**:
- [ ] Redshift view returns rows (not empty)
- [ ] Row count is within expected range
- [ ] If comparable, counts match Postgres (within reasonable delta for time-based filters)

### 6. Sample Data Validation
Compare a few sample records:

```sql
-- Get sample from Redshift
SELECT * FROM public.v_nimbus_runs_dp_km 
WHERE run_uuid = '<some_known_uuid>'
LIMIT 1;
```

**Validate**:
- [ ] All 53 columns are present
- [ ] Column names match exactly
- [ ] Values look reasonable
- [ ] No unexpected NULLs
- [ ] Timestamp formats are correct

### 7. Window Function Validation
Verify the window function works correctly:

```sql
SELECT 
    remcmcellid,
    run_time_created,
    run_status,
    job_latest_run_status,
    COUNT(*) OVER (PARTITION BY remcmcellid) as jobs_per_cell
FROM public.v_nimbus_runs_dp_km
WHERE remcmcellid IS NOT NULL
ORDER BY remcmcellid, run_time_created
LIMIT 20;
```

**Expected Results**:
- [ ] `job_latest_run_status` shows the latest status per `remcmcellid`
- [ ] Values are consistent within each partition
- [ ] No errors in window function execution

### 8. Grants Validation
Verify permissions were applied:

```sql
-- Check view ownership and permissions
SELECT 
    schemaname,
    tablename,
    tableowner,
    CASE 
        WHEN has_table_privilege('"IAMR:cu-rem-pm-users"', schemaname || '.' || tablename, 'SELECT') 
        THEN 'Yes' ELSE 'No' 
    END as cu_rem_pm_users_access,
    CASE 
        WHEN has_table_privilege('quicksight_user', schemaname || '.' || tablename, 'SELECT') 
        THEN 'Yes' ELSE 'No' 
    END as quicksight_user_access
FROM pg_tables
WHERE schemaname = 'public' 
  AND tablename = 'v_nimbus_runs_dp_km';
```

**Expected Results**:
- [ ] View exists in public schema
- [ ] Both roles have SELECT access
- [ ] Owner is as expected

### 9. Performance Check
Test query performance:

```sql
-- Simple aggregation query
SELECT 
    run_cloud_region,
    run_status,
    COUNT(*) as count,
    AVG(CASE WHEN exec_cpu_hours::float > 0 THEN exec_cpu_hours::float END) as avg_cpu_hours
FROM public.v_nimbus_runs_dp_km
GROUP BY run_cloud_region, run_status
ORDER BY count DESC;
```

**Expected Results**:
- [ ] Query completes in reasonable time (< 1 minute for typical dataset)
- [ ] Results are accurate
- [ ] No timeouts or resource issues

## Post-Deployment Validation

### 10. Integration Testing
- [ ] QuickSight dashboards using this view still work
- [ ] Any dependent queries/reports return expected results
- [ ] No performance degradation in downstream systems

### 11. Data Quality Checks
- [ ] Spot-check 5-10 records against source data
- [ ] Verify critical business metrics haven't changed
- [ ] Check for any data loss (unexpected NULLs, missing records)

## Rollback Plan

If issues are found:
```sql
-- Drop the view
DROP VIEW public.v_nimbus_runs_dp_km;

-- Revoke grants if needed
REVOKE SELECT ON public.v_nimbus_runs_dp_km FROM "IAMR:cu-rem-pm-users";
REVOKE SELECT ON public.v_nimbus_runs_dp_km FROM quicksight_user;
```

## Sign-Off

- [ ] All validations passed
- [ ] Stakeholders notified
- [ ] Documentation updated
- [ ] Deployment approved

**Deployed by**: ________________  
**Date**: ________________  
**Version used**: [ ] Version 1 (VARCHAR) [ ] Version 2 (Numeric)  
**Notes**: ____________________________________
