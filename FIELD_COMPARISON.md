# Field-by-Field Comparison: Postgres vs Redshift View

## All 52 Fields - Matching Status

| # | Field Name | Postgres Type | Redshift Type (Version 1) | Redshift Type (Version 2) | Match Status |
|---|------------|---------------|---------------------------|---------------------------|--------------|
| 1 | run_id | integer | integer | integer | ✅ Exact |
| 2 | run_uuid | uuid/text | varchar | varchar | ✅ Compatible |
| 3 | run_time_created | timestamp | date | date | ⚠️ Cast to date |
| 4 | run_status | varchar | varchar | varchar | ✅ Exact |
| 5 | run_nevo_topic_identifier | varchar | varchar | varchar | ✅ Exact |
| 6 | run_name | varchar | varchar | varchar | ✅ Exact |
| 7 | run_map_name | varchar | varchar | varchar | ✅ Exact |
| 8 | run_end_time | timestamp | date | date | ⚠️ Cast to date |
| 9 | run_cloud_region | varchar | varchar | varchar | ✅ Exact |
| 10 | created_by_user | varchar | varchar | varchar | ✅ Exact |
| 11 | nimbus_runs_failure_reason | varchar | varchar | varchar | ✅ Exact |
| 12 | remcmcellid | text | varchar | varchar | ✅ Compatible |
| 13 | user | text | varchar | varchar | ✅ Compatible |
| 14 | runtype | text | varchar | varchar | ✅ Compatible |
| 15 | testtype | text | varchar | varchar | ✅ Compatible |
| 16 | customer | text | varchar | varchar | ✅ Compatible |
| 17 | workload | text | varchar | varchar | ✅ Compatible |
| 18 | environment | text | varchar | varchar | ✅ Compatible |
| 19 | projecttype | text | varchar | varchar | ✅ Compatible |
| 20 | triggertype | text | varchar | varchar | ✅ Compatible |
| 21 | remcmcellsize | text | varchar | varchar | ✅ Compatible |
| 22 | remcmbasemapname | text | varchar | varchar | ✅ Compatible |
| 23 | initiator | text | varchar | varchar | ✅ Compatible |
| 24 | gitbranch | text | varchar | varchar | ✅ Compatible |
| 25 | cfversion | text | varchar | varchar | ✅ Compatible |
| 26 | remallocationcategory | text | varchar | varchar | ✅ Compatible |
| 27 | remprocessmapname | text | varchar | varchar | ✅ Compatible |
| 28 | remprocessmapsize | text | varchar | varchar | ✅ Compatible |
| 29 | clustername | text | varchar | varchar | ✅ Compatible |
| 30 | basemapuuid | text | varchar | varchar | ✅ Compatible |
| 31 | step_team | text | varchar | varchar | ✅ Compatible |
| 32 | step_tech | text | varchar | varchar | ✅ Compatible |
| 33 | process_metadata_evaluator | text | varchar | varchar | ✅ Compatible |
| 34 | step_id | integer | integer | integer | ✅ Exact |
| 35 | step_uuid | uuid/text | varchar | varchar | ✅ Compatible |
| 36 | step_time_created | timestamp | date | date | ⚠️ Cast to date |
| 37 | step_name | varchar | varchar | varchar | ✅ Exact |
| 38 | step_status | varchar | varchar | varchar | ✅ Exact |
| 39 | step_failure_reason | integer | integer | integer | ✅ Exact |
| 40 | step_start_time | timestamp | date | date | ⚠️ Cast to date |
| 41 | step_end_time | timestamp | date | date | ⚠️ Cast to date |
| 42 | step_number_of_cores | integer | integer | integer | ✅ Exact |
| 43 | step_original_run_id | integer | integer | integer | ✅ Exact |
| 44 | step_cloud_region | varchar | varchar | varchar | ✅ Exact |
| 45 | nimbus_steps_failure_reason | varchar | varchar | varchar | ✅ Exact |
| 46 | original_run_uuid | uuid/text | varchar | varchar | ✅ Compatible |
| 47 | job_latest_run_status | varchar | varchar | varchar | ✅ Exact |
| 48 | fractional_factor | text | varchar | float | ⚠️ Version difference |
| 49 | exec_cpu_hours | text | varchar | float | ⚠️ Version difference |
| 50 | executor_cores | text | varchar | int | ⚠️ Version difference |
| 51 | driver_cpu_hours | text | varchar | float | ⚠️ Version difference |
| 52 | app_required_cores | text | varchar | float | ⚠️ Version difference |
| 53 | step_app_duration_in_minutes | text | varchar | float | ⚠️ Version difference |

## Summary

- **Total Fields**: 53
- **✅ Exact/Compatible Matches**: 42 fields
- **⚠️ Version-Dependent**: 6 fields (statistics fields - rows 48-53)
- **⚠️ Date Cast**: 5 fields (timestamp → date - rows 3, 8, 36, 40, 41)

## Version Differences

### Version 1: VARCHAR Statistics (v_nimbus_runs_dp_km_redshift.sql)
- Statistics fields (48-53) remain as **VARCHAR**
- Timestamp fields (3, 8, 36, 40, 41) cast to **DATE**
- Date casting matches MV_RUNS_DP_KM table pattern
- Requires explicit casting in queries for numeric operations on statistics

### Version 2: Numeric Statistics (v_nimbus_runs_dp_km_redshift_with_numeric_casting.sql)
- Statistics fields (48-53) cast to **FLOAT/INT**
- Timestamp fields (3, 8, 36, 40, 41) cast to **DATE**
- Handles 'NaN' and empty string values using NULLIF
- Better performance for queries with numeric operations
- Fully matches the MV_RUNS_DP_KM table approach

## Recommendation

**Use Version 1 if**:
- You want VARCHAR statistics fields (simpler, no NaN handling needed)
- You're okay with date-only fields (no time component)

**Use Version 2 if**:
- You frequently perform calculations on statistics fields
- You want to fully match the existing MV_RUNS_DP_KM table pattern
- You prefer explicit NULL handling for invalid numeric values

**Both versions now**:
- Cast timestamp fields to DATE (matching table pattern)
- Use late binding (`WITH NO SCHEMA BINDING`)
- Include all 53 fields from original view
