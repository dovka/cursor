# Complete Field List - v_nimbus_runs_dp_km

## Total Fields: 53

All fields from the original Postgres view are preserved in the Redshift conversion.

---

## Field List (in order as they appear in SELECT)

| # | Field Name | Source | Type | Notes |
|---|------------|--------|------|-------|
| 1 | run_id | nr.id | integer | Primary identifier for run |
| 2 | run_uuid | nr.uuid | varchar | Unique identifier for run |
| 3 | run_time_created | nr.time_created | timestamp | Run creation timestamp |
| 4 | run_status | nr.status | varchar | Run status |
| 5 | run_nevo_topic_identifier | nr.nevo_topic_identifier | varchar | Nevo topic ID |
| 6 | run_name | nr.run_name | varchar | Name of the run |
| 7 | run_map_name | nr.map_name | varchar | Map name for run |
| 8 | run_end_time | nr.end_time | timestamp | Run end timestamp |
| 9 | run_cloud_region | nr.cloud_region | varchar | Cloud region for run |
| 10 | created_by_user | nr.created_by_user | varchar | User who created run |
| 11 | nimbus_runs_failure_reason | nr.nimbus_runs_failure_reason | varchar | Human-readable failure reason (from join) |
| 12 | remcmcellid | ns.remcmcellid | varchar | RemCM Cell ID from JSON |
| 13 | user | ns."user" | varchar | User from JSON (quoted - reserved word) |
| 14 | runtype | ns.runtype | varchar | Run type from JSON |
| 15 | testtype | ns.testtype | varchar | Test type from JSON |
| 16 | customer | ns.customer | varchar | Customer from JSON |
| 17 | workload | ns.workload | varchar | Workload from JSON |
| 18 | environment | ns.environment | varchar | Environment from JSON |
| 19 | projecttype | ns.projecttype | varchar | Project type from JSON |
| 20 | triggertype | ns.triggertype | varchar | Trigger type from JSON |
| 21 | remcmcellsize | ns.remcmcellsize | varchar | RemCM Cell Size from JSON |
| 22 | remcmbasemapname | ns.remcmbasemapname | varchar | RemCM Base Map Name from JSON |
| 23 | initiator | ns.initiator | varchar | Initiator from JSON |
| 24 | gitbranch | ns.gitbranch | varchar | Git branch from JSON |
| 25 | cfversion | ns.cfversion | varchar | CF Version from JSON |
| 26 | remallocationcategory | ns.remallocationcategory | varchar | RemAllocation Category from JSON |
| 27 | remprocessmapname | ns.remprocessmapname | varchar | RemProcess Map Name from JSON |
| 28 | remprocessmapsize | ns.remprocessmapsize | varchar | RemProcess Map Size from JSON |
| 29 | clustername | ns.clustername | varchar | Cluster name from JSON |
| 30 | basemapuuid | ns.basemapuuid | varchar | Base map UUID from JSON |
| 31 | step_team | ns.step_team | varchar | Team from JSON |
| 32 | step_tech | ns.step_tech | varchar | Tech from JSON |
| 33 | process_metadata_evaluator | ns.process_metadata_evaluator | varchar | Evaluator from JSON |
| 34 | step_id | ns.id | integer | Primary identifier for step |
| 35 | step_uuid | ns.uuid | varchar | Unique identifier for step |
| 36 | step_time_created | ns.time_created | timestamp | Step creation timestamp |
| 37 | step_name | ns.step_name | varchar | Name of the step |
| 38 | step_status | ns.status | varchar | Step status |
| 39 | step_failure_reason | ns.failure_reason | integer | Raw failure reason value |
| 40 | step_start_time | ns.start_time | timestamp | Step start timestamp |
| 41 | step_end_time | ns.end_time | timestamp | Step end timestamp |
| 42 | step_number_of_cores | ns.number_of_cores | integer | Number of cores for step |
| 43 | step_original_run_id | ns.original_run_id | integer | Original run ID reference |
| 44 | step_cloud_region | ns.cloud_region | varchar | Cloud region for step |
| 45 | nimbus_steps_failure_reason | ns.nimbus_steps_failure_reason | varchar | Human-readable failure reason (from join) |
| 46 | original_run_uuid | nr2.uuid | varchar | UUID of original run |
| 47 | job_latest_run_status | LAST_VALUE(...) | varchar | Latest status per remcmcellid (window function) |
| 48 | fractional_factor | ns.fractional_factor | varchar/float* | Fractional factor from JSON |
| 49 | exec_cpu_hours | ns.exec_cpu_hours | varchar/float* | Execution CPU hours from JSON |
| 50 | executor_cores | ns.executor_cores | varchar/int* | Executor cores from JSON |
| 51 | driver_cpu_hours | ns.driver_cpu_hours | varchar/float* | Driver CPU hours from JSON |
| 52 | app_required_cores | ns.app_required_cores | varchar/float* | App required cores from JSON |
| 53 | step_app_duration_in_minutes | ns.step_app_duration_in_minutes | varchar/float* | App duration in minutes from JSON |

\* **Type depends on version**:
- Version 1: varchar
- Version 2: float (or int for executor_cores)

---

## Fields by Category

### Run Information (11 fields)
1. run_id
2. run_uuid
3. run_time_created
4. run_status
5. run_nevo_topic_identifier
6. run_name
7. run_map_name
8. run_end_time
9. run_cloud_region
10. created_by_user
11. nimbus_runs_failure_reason

### JSON Metadata - Resource Tags (22 fields)
12. remcmcellid
13. user
14. runtype
15. testtype
16. customer
17. workload
18. environment
19. projecttype
20. triggertype
21. remcmcellsize
22. remcmbasemapname
23. initiator
24. gitbranch
25. cfversion
26. remallocationcategory
27. remprocessmapname
28. remprocessmapsize
29. clustername (from metadata_json root)
30. basemapuuid (from metadata_json root)
31. step_team
32. step_tech
33. process_metadata_evaluator

### Step Information (12 fields)
34. step_id
35. step_uuid
36. step_time_created
37. step_name
38. step_status
39. step_failure_reason
40. step_start_time
41. step_end_time
42. step_number_of_cores
43. step_original_run_id
44. step_cloud_region
45. nimbus_steps_failure_reason

### Computed/Joined Fields (2 fields)
46. original_run_uuid
47. job_latest_run_status

### Statistics from JSON (6 fields)
48. fractional_factor
49. exec_cpu_hours
50. executor_cores
51. driver_cpu_hours
52. app_required_cores
53. step_app_duration_in_minutes

---

## Fields Present in View but NOT in MV_RUNS_DP_KM Table

The following 9 fields exist in the view but were omitted from the MV_RUNS_DP_KM table:

1. **run_id** - Integer ID of the run (table only has run_uuid)
2. **step_id** - Integer ID of the step (table only has step_uuid)
3. **step_failure_reason** - Raw failure reason value (table only has nimbus_steps_failure_reason)
4. **step_number_of_cores** - Number of cores
5. **step_original_run_id** - Original run ID reference
6. **step_cloud_region** - Cloud region for step
7. **remcmcellsize** - RemCM Cell Size
8. **remprocessmapsize** - RemProcess Map Size
9. **clustername** - Cluster name

**All 9 fields are included in both Redshift view versions.**

---

## Fields in MV_RUNS_DP_KM Table but NOT in View

The table excluded the integer ID fields in favor of UUIDs only, but otherwise the view has MORE fields than the table.

---

## Data Type Differences Between Versions

| Field | Postgres View | Redshift V1 | Redshift V2 |
|-------|---------------|-------------|-------------|
| fractional_factor | text | varchar | float |
| exec_cpu_hours | text | varchar | float |
| executor_cores | text | varchar | int |
| driver_cpu_hours | text | varchar | float |
| app_required_cores | text | varchar | float |
| step_app_duration_in_minutes | text | varchar | float |

All other 47 fields have identical or compatible types across all versions.

---

## JSON Extraction Paths

### From `resources_tags` object:
- RemCMCellId → remcmcellid
- User → user
- RunType → runtype
- TestType → testtype
- Customer → customer
- Workload → workload
- Environment → environment
- ProjectType → projecttype
- TriggerType → triggertype
- RemCMCellSize → remcmcellsize
- RemCMBaseMapName → remcmbasemapname
- Initiator → initiator
- GitBranch → gitbranch
- CFVersion → cfversion
- RemAllocationCategory → remallocationcategory
- RemProcessMapName → remprocessmapname
- RemProcessMapSize → remprocessmapsize
- Team → step_team
- Tech → step_tech

### From `process_metadata` object:
- EVALUATOR → process_metadata_evaluator

### From `statistics` object:
- exec_cpu_hours → exec_cpu_hours
- executor_cores → executor_cores
- driver_cpu_hours → driver_cpu_hours
- app_required_cores → app_required_cores
- duration_in_minutes → step_app_duration_in_minutes

### From root level:
- cluster_name → clustername
- base_map_uuid → basemapuuid
- fractional_factor → fractional_factor

---

## Summary

✅ All 53 fields preserved  
✅ Field names match exactly  
✅ Field order matches exactly  
✅ 9 additional fields vs MV_RUNS_DP_KM table  
✅ Only difference: 6 statistics fields (varchar vs numeric)
