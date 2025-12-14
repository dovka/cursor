DROP TABLE MV_NUMBER_OF_DRIVES_PER_MAP;

CREATE TABLE MV_NUMBER_OF_DRIVES_PER_MAP AS
WITH ns AS (
    -- nevo_shared_prod_oems source
    SELECT
        metadata,
        name,
        uuid,
        status,
        'nevo_shared_prod_oems' AS source
    FROM datalake_glue_catalog.db1_shared_dev_nevo_shared_prod_oems__nevodb__public_nevo_step
    WHERE created::timestamp >= DATEADD(month, -6, GETDATE())
      AND name IN ('MapManipulation','DrivesData','AggregateMapMatching',
                   'ExportRTG','ExportObs','SurgicalRemapRanges','DP')
    
    UNION ALL
    
    -- nevo_shared_prod_av source
    SELECT
        metadata,
        name,
        uuid,
        status,
        'nevo_shared_prod_av' AS source
    FROM datalake_glue_catalog.db1_shared_dev_nevo_shared_prod_av__nevodb__public_nevo_step
    WHERE created::timestamp >= DATEADD(month, -6, GETDATE())
      AND name IN ('MapManipulation','DrivesData','AggregateMapMatching',
                   'ExportRTG','ExportObs','SurgicalRemapRanges','DP')
    
    UNION ALL
    
    -- nevo_shared_dev source
    SELECT
        metadata,
        name,
        uuid,
        status,
        'nevo_shared_dev' AS source
    FROM datalake_glue_catalog.db1_shared_dev_nevo_shared_dev__nevodb__public_nevo_step
    WHERE created::timestamp >= DATEADD(month, -6, GETDATE())
      AND name IN ('MapManipulation','DrivesData','AggregateMapMatching',
                   'ExportRTG','ExportObs','SurgicalRemapRanges','DP')
),
nm AS (
    -- nevo_shared_prod_oems source
    SELECT
        uuid AS mapcreationrun_uuid,
        name AS run_name,
        metadata,
        status AS map_creation_run_status,
        created::timestamp AS map_creation_run_time_created,
        'nevo_shared_prod_oems' AS source
    FROM datalake_glue_catalog.db1_shared_dev_nevo_shared_prod_oems__nevodb__public_nevo_mapcreationrun
    WHERE created::timestamp >= DATEADD(month, -6, GETDATE())
    
    UNION ALL
    
    -- nevo_shared_prod_av source
    SELECT
        uuid,
        name,
        metadata,
        status,
        created::timestamp,
        'nevo_shared_prod_av' AS source
    FROM datalake_glue_catalog.db1_shared_dev_nevo_shared_prod_av__nevodb__public_nevo_mapcreationrun
    WHERE created::timestamp >= DATEADD(month, -6, GETDATE())
    
    UNION ALL
    
    -- nevo_shared_dev source
    SELECT
        uuid AS mapcreationrun_uuid,
        name AS run_name,
        metadata,
        status AS map_creation_run_status,
        created::timestamp AS map_creation_run_time_created,
        'nevo_shared_dev' AS source
    FROM datalake_glue_catalog.db1_shared_dev_nevo_shared_dev__nevodb__public_nevo_mapcreationrun
    WHERE created::timestamp >= DATEADD(month, -6, GETDATE())
),
steps AS (
    -- nevo_shared_prod_oems source
    SELECT
        sr.mapcreationrun_id,
        ns.uuid       AS step_uuid,
        ns.name       AS step_name,
        ns.metadata   AS step_metadata,
        ns.status     AS step_status,
        ns.source
    FROM datalake_glue_catalog.db1_shared_dev_nevo_shared_prod_oems__nevodb__public_nevo_step_runs sr
    JOIN ns
      ON ns.uuid = sr.step_id
     AND ns.source = 'nevo_shared_prod_oems'
    
    UNION ALL
    
    -- nevo_shared_prod_av source
    SELECT
        sr.mapcreationrun_id,
        ns.uuid,
        ns.name,
        ns.metadata,
        ns.status,
        ns.source
    FROM datalake_glue_catalog.db1_shared_dev_nevo_shared_prod_av__nevodb__public_nevo_step_runs sr
    JOIN ns
      ON ns.uuid = sr.step_id
     AND ns.source = 'nevo_shared_prod_av'
    
    UNION ALL
    
    -- nevo_shared_dev source
    SELECT
        sr.mapcreationrun_id,
        ns.uuid       AS step_uuid,
        ns.name       AS step_name,
        ns.metadata   AS step_metadata,
        ns.status     AS step_status,
        ns.source
    FROM datalake_glue_catalog.db1_shared_dev_nevo_shared_dev__nevodb__public_nevo_step_runs sr
    JOIN ns
      ON ns.uuid = sr.step_id
     AND ns.source = 'nevo_shared_dev'
)
SELECT
    nm.mapcreationrun_uuid,
    nm.run_name,
    JSON_EXTRACT_PATH_TEXT(nm.metadata,'map_name',true) AS map_name,
    nm.map_creation_run_status,
    nm.map_creation_run_time_created,
    MAX(CASE WHEN step_name='MapManipulation'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','number of drives',true) END)
        AS mapmanipulation_number_of_drives,
    MAX(CASE WHEN step_name='MapManipulation'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','number of links',true) END)
        AS mapmanipulation_number_of_links,
    MAX(CASE WHEN step_name='MapManipulation'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','Length of map(KM)',true) END)
        AS mapmanipulation_length_of_map_km,
    MAX(CASE WHEN step_name='MapManipulation'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','number of super links',true) END)
        AS mapmanipulation_num_of_super_links,
    MAX(CASE WHEN step_name='MapManipulation'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','number of super vertices',true) END)
        AS mapmanipulation_number_of_super_vertices,
    MAX(CASE WHEN step_name='MapManipulation'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','total_drives_length_km',true) END)
        AS mapmanipulation_total_drives_length_km,
    MAX(CASE WHEN step_name='DrivesData'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','Num of H5s',true) END)
        AS drivesdata_num_of_h5s,
    MAX(CASE WHEN step_name='DrivesData'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','Succeeded',true) END)
        AS drivesdata_succeeded,
    MAX(CASE WHEN step_name='DrivesData'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','SpeedFactorNotInRange',true) END)
        AS drivesdata_speed_factor_not_in_range,
    MAX(CASE WHEN step_name='DrivesData'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','total_drives_length_km',true) END)
        AS drivesdata_total_drives_length_km,
    MAX(CASE WHEN step_name='DrivesData'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','success_drives_length_km',true) END)
        AS drivesdata_success_drives_length_km,
    MAX(CASE WHEN step_name='AggregateMapMatching'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','number of links',true) END)
        AS aggregatemapmatching_number_of_links,
    MAX(CASE WHEN step_name='AggregateMapMatching'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','number of drives',true) END)
        AS aggregatemapmatching_number_of_drives,
    MAX(CASE WHEN step_name='AggregateMapMatching'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','Length of map(KM)',true) END)
        AS aggregatemapmatching_length_of_map_km,
    MAX(CASE WHEN step_name='AggregateMapMatching'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','number of super links',true) END)
        AS aggregatemapmatching_num_of_super_links,
    MAX(CASE WHEN step_name='AggregateMapMatching'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','number of super vertices',true) END)
        AS aggregatemapmatching_number_of_super_vertices,
    MAX(CASE WHEN step_name='AggregateMapMatching'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','total_drives_length_km',true) END)
        AS aggregatemapmatching_total_drives_length_km,
    MAX(CASE WHEN step_name='ExportRTG'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'num_rtgs',true) END)
        AS exportrtg_num_rtgs,
    MAX(CASE WHEN step_name='ExportObs'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'lms',true) END)
        AS exportobs_lms,
    MAX(CASE WHEN step_name='ExportObs'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'poles',true) END)
        AS exportobs_poles,
    MAX(CASE WHEN step_name='ExportObs'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'road_edges',true) END)
        AS exportobs_road_edges,
    MAX(CASE WHEN step_name='ExportObs'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'road_points',true) END)
        AS exportobs_road_points,
    MAX(CASE WHEN step_name='SurgicalRemapRanges'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','total red ranges length on links',true) END)
        AS total_red_ranges_length_on_links,
    MAX(CASE WHEN step_name='SurgicalRemapRanges'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','total blue ranges length on links',true) END)
        AS total_blue_ranges_length_on_links,
    MAX(CASE WHEN step_name='SurgicalRemapRanges'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','total green ranges length on links',true) END)
        AS total_green_ranges_length_on_links,
    MAX(CASE WHEN step_name='SurgicalRemapRanges'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','total yellow ranges length on links',true) END)
        AS total_yellow_ranges_length_on_links,
    MAX(CASE WHEN step_name='DP'
        THEN JSON_EXTRACT_PATH_TEXT(step_metadata,'statistics','total_dp_length',true) END)
        AS dp_total_dp_length,
    MAX(CASE WHEN step_name='MapManipulation' THEN step_status END)
        AS step_status_mapmanipulation,
    MAX(CASE WHEN step_name='DrivesData' THEN step_status END)
        AS step_status_drivesdata,
    MAX(CASE WHEN step_name='AggregateMapMatching' THEN step_status END)
        AS step_status_aggregatemapmatching,
    MAX(CASE WHEN step_name='ExportRTG' THEN step_status END)
        AS step_status_exportrtg,
    MAX(CASE WHEN step_name='ExportObs' THEN step_status END)
        AS step_status_exportobs,
    nm.source
FROM nm LEFT JOIN steps
  ON nm.mapcreationrun_uuid = steps.mapcreationrun_id
 AND nm.source = steps.source
GROUP BY
    nm.mapcreationrun_uuid,
    nm.run_name,
    nm.metadata,
    nm.map_creation_run_status,
    nm.map_creation_run_time_created,
    nm.source;
