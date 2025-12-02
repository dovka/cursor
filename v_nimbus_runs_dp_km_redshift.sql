-- ============================================================================
-- ASSUMPTIONS TO CONFIRM:
-- ============================================================================
-- 1. Table name pattern: Using datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_* 
--    (same as the example MV_RUNS_DP_KM table)
-- 2. Time filter: Keep the 70-day filter (converted from Postgres interval to Redshift DATEADD)
-- 3. JSON validation: Added IS_VALID_JSON() check for metadata_json (as in example)
-- 4. JSON extraction: Using JSON_EXTRACT_PATH_TEXT() with case-sensitive flag = true
-- 5. Data types for JSON-extracted fields:
--    - fractional_factor: VARCHAR (extracted as text) - DIFFERENT from table which casts to float
--    - exec_cpu_hours: VARCHAR (extracted as text) - DIFFERENT from table which casts to float
--    - executor_cores: VARCHAR (extracted as text) - DIFFERENT from table which casts to int
--    - driver_cpu_hours: VARCHAR (extracted as text) - DIFFERENT from table which casts to float
--    - app_required_cores: VARCHAR (extracted as text) - DIFFERENT from table which casts to float
--    - step_app_duration_in_minutes: VARCHAR (extracted as text) - DIFFERENT from table which casts to float
--    NOTE: To match the view exactly, these remain as VARCHAR. If numeric operations are needed,
--          consider casting them like in the MV_RUNS_DP_KM table example.
-- 6. Date/timestamp fields: Keep as timestamp (NOT casting to date like in the table example)
--    - This preserves exact field types from the original view
-- 7. Window function: Changed from RANGE to ROWS BETWEEN (Redshift requirement)
-- 8. Missing columns in view that exist in original:
--    - The view includes ALL columns from original Postgres view including:
--      * run_id, step_id (integer IDs)
--      * step_failure_reason (the raw value, not just the name)
--      * step_number_of_cores, step_original_run_id, step_cloud_region
--      * remcmcellsize, remprocessmapsize, clustername
--    These are PRESENT in this Redshift view but ABSENT from the MV_RUNS_DP_KM table
-- 9. Schema: Creating in public schema
-- 10. Grants: Using same roles as example (IAMR:cu-rem-pm-users and quicksight_user)
-- ============================================================================

-- View: public.v_nimbus_runs_dp_km

-- DROP VIEW public.v_nimbus_runs_dp_km;

CREATE OR REPLACE VIEW public.v_nimbus_runs_dp_km
WITH NO SCHEMA BINDING
AS
WITH nr AS (
    SELECT
        nimbus_runs.id,
        nimbus_runs.uuid,
        nimbus_runs.time_created,
        nimbus_runs.status,
        nimbus_runs.failure_reason,
        nimbus_runs.nevo_topic_identifier,
        nimbus_runs.run_name,
        nimbus_runs.map_name,
        nimbus_runs.end_time,
        nimbus_runs.cloud_region,
        nimbus_runs.created_by_user,
        failure_reasons.name AS nimbus_runs_failure_reason
    FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_nimbus_runs nimbus_runs
    LEFT JOIN datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_failure_reasons failure_reasons
        ON failure_reasons.value = nimbus_runs.failure_reason
    WHERE nimbus_runs.time_created >= DATEADD(day, -70, GETDATE())
),
ns AS (
    SELECT
        nimbus_steps.id,
        nimbus_steps.uuid,
        nimbus_steps.time_created,
        nimbus_steps.step_name,
        nimbus_steps.status,
        nimbus_steps.failure_reason,
        nimbus_steps.start_time,
        nimbus_steps.end_time,
        nimbus_steps.number_of_cores,
        nimbus_steps.original_run_id,
        nimbus_steps.cloud_region,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'RemCMCellId', true) AS remcmcellid,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'User', true) AS "user",
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'RunType', true) AS runtype,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'TestType', true) AS testtype,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'Customer', true) AS customer,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'Workload', true) AS workload,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'Environment', true) AS environment,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'ProjectType', true) AS projecttype,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'TriggerType', true) AS triggertype,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'RemCMCellSize', true) AS remcmcellsize,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'RemCMBaseMapName', true) AS remcmbasemapname,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'Initiator', true) AS initiator,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'GitBranch', true) AS gitbranch,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'CFVersion', true) AS cfversion,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'RemAllocationCategory', true) AS remallocationcategory,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'RemProcessMapName', true) AS remprocessmapname,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'RemProcessMapSize', true) AS remprocessmapsize,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'cluster_name', true) AS clustername,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'base_map_uuid', true) AS basemapuuid,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'Team', true) AS step_team,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'resources_tags', 'Tech', true) AS step_tech,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'process_metadata', 'EVALUATOR', true) AS process_metadata_evaluator,
        failure_reasons.name AS nimbus_steps_failure_reason,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'fractional_factor', true) AS fractional_factor,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'statistics', 'exec_cpu_hours', true) AS exec_cpu_hours,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'statistics', 'executor_cores', true) AS executor_cores,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'statistics', 'driver_cpu_hours', true) AS driver_cpu_hours,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'statistics', 'app_required_cores', true) AS app_required_cores,
        JSON_EXTRACT_PATH_TEXT(nimbus_steps.metadata_json, 'statistics', 'duration_in_minutes', true) AS step_app_duration_in_minutes
    FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_nimbus_steps nimbus_steps
    LEFT JOIN datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_failure_reasons failure_reasons
        ON failure_reasons.value = nimbus_steps.failure_reason
    WHERE nimbus_steps.time_created >= DATEADD(day, -70, GETDATE())
        AND nimbus_steps.metadata_json IS NOT NULL 
        AND IS_VALID_JSON(nimbus_steps.metadata_json)
)
SELECT
    nr.id AS run_id,
    nr.uuid AS run_uuid,
    nr.time_created AS run_time_created,
    nr.status AS run_status,
    nr.nevo_topic_identifier AS run_nevo_topic_identifier,
    nr.run_name,
    nr.map_name AS run_map_name,
    nr.end_time AS run_end_time,
    nr.cloud_region AS run_cloud_region,
    nr.created_by_user,
    nr.nimbus_runs_failure_reason,
    ns.remcmcellid,
    ns."user",
    ns.runtype,
    ns.testtype,
    ns.customer,
    ns.workload,
    ns.environment,
    ns.projecttype,
    ns.triggertype,
    ns.remcmcellsize,
    ns.remcmbasemapname,
    ns.initiator,
    ns.gitbranch,
    ns.cfversion,
    ns.remallocationcategory,
    ns.remprocessmapname,
    ns.remprocessmapsize,
    ns.clustername,
    ns.basemapuuid,
    ns.step_team,
    ns.step_tech,
    ns.process_metadata_evaluator,
    ns.id AS step_id,
    ns.uuid AS step_uuid,
    ns.time_created AS step_time_created,
    ns.step_name,
    ns.status AS step_status,
    ns.failure_reason AS step_failure_reason,
    ns.start_time AS step_start_time,
    ns.end_time AS step_end_time,
    ns.number_of_cores AS step_number_of_cores,
    ns.original_run_id AS step_original_run_id,
    ns.cloud_region AS step_cloud_region,
    ns.nimbus_steps_failure_reason,
    nr2.uuid AS original_run_uuid,
    LAST_VALUE(nr.status) OVER (
        PARTITION BY ns.remcmcellid 
        ORDER BY nr.time_created 
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS job_latest_run_status,
    ns.fractional_factor,
    ns.exec_cpu_hours,
    ns.executor_cores,
    ns.driver_cpu_hours,
    ns.app_required_cores,
    ns.step_app_duration_in_minutes
FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_run_to_step_association run_to_step_association
JOIN nr ON nr.id = run_to_step_association.run_id
JOIN ns ON ns.id = run_to_step_association.step_id
JOIN nr nr2 ON nr2.id = ns.original_run_id;

-- Grants
GRANT SELECT ON public.v_nimbus_runs_dp_km TO "IAMR:cu-rem-pm-users";
GRANT SELECT ON public.v_nimbus_runs_dp_km TO quicksight_user;
