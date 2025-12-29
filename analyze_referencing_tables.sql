-- Analysis: Identify which referencing tables already have main_quadkey and map_id columns
-- This must be run BEFORE creating the migration script

-- List of tables that reference signs(id) via foreign keys:
-- 1. alternating_lane_sign_association
-- 2. dp_stop_point_group_to_tfl_associations
-- 3. dp_stop_point_ra_association
-- 4. dp_stop_point_sign_association
-- 5. dp_stop_point_tlf_association
-- 6. ltwa_dp_stop_point_to_tfl_association
-- 7. sign_alternative_observation_associations
-- 8. sign_supplementary_type_associations
-- 9. sign_to_dp_association
-- 10. sign_to_edge_association

\echo '============================================'
\echo 'SIGNS TABLE - REFERENCING TABLES ANALYSIS'
\echo '============================================'
\echo ''

-- Check for main_quadkey column in each referencing table
\echo 'Checking for main_quadkey column:'
\echo '----------------------------------'

SELECT 
    table_name,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
    AND table_name IN (
        'alternating_lane_sign_association',
        'dp_stop_point_group_to_tfl_associations',
        'dp_stop_point_ra_association',
        'dp_stop_point_sign_association',
        'dp_stop_point_tlf_association',
        'ltwa_dp_stop_point_to_tfl_association',
        'sign_alternative_observation_associations',
        'sign_supplementary_type_associations',
        'sign_to_dp_association',
        'sign_to_edge_association'
    )
    AND column_name = 'main_quadkey'
ORDER BY table_name;

\echo ''
\echo 'Checking for map_id column:'
\echo '---------------------------'

SELECT 
    table_name,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
    AND table_name IN (
        'alternating_lane_sign_association',
        'dp_stop_point_group_to_tfl_associations',
        'dp_stop_point_ra_association',
        'dp_stop_point_sign_association',
        'dp_stop_point_tlf_association',
        'ltwa_dp_stop_point_to_tfl_association',
        'sign_alternative_observation_associations',
        'sign_supplementary_type_associations',
        'sign_to_dp_association',
        'sign_to_edge_association'
    )
    AND column_name = 'map_id'
ORDER BY table_name;

\echo ''
\echo 'Summary - Tables that NEED new columns:'
\echo '---------------------------------------'

-- Tables that need main_quadkey column
WITH tables_needing_quadkey AS (
    SELECT DISTINCT t.table_name
    FROM information_schema.tables t
    WHERE t.table_schema = 'public'
        AND t.table_name IN (
            'alternating_lane_sign_association',
            'dp_stop_point_group_to_tfl_associations',
            'dp_stop_point_ra_association',
            'dp_stop_point_sign_association',
            'dp_stop_point_tlf_association',
            'ltwa_dp_stop_point_to_tfl_association',
            'sign_alternative_observation_associations',
            'sign_supplementary_type_associations',
            'sign_to_dp_association',
            'sign_to_edge_association'
        )
        AND NOT EXISTS (
            SELECT 1 
            FROM information_schema.columns c
            WHERE c.table_schema = 'public'
                AND c.table_name = t.table_name
                AND c.column_name = 'main_quadkey'
        )
),
tables_needing_mapid AS (
    SELECT DISTINCT t.table_name
    FROM information_schema.tables t
    WHERE t.table_schema = 'public'
        AND t.table_name IN (
            'alternating_lane_sign_association',
            'dp_stop_point_group_to_tfl_associations',
            'dp_stop_point_ra_association',
            'dp_stop_point_sign_association',
            'dp_stop_point_tlf_association',
            'ltwa_dp_stop_point_to_tfl_association',
            'sign_alternative_observation_associations',
            'sign_supplementary_type_associations',
            'sign_to_dp_association',
            'sign_to_edge_association'
        )
        AND NOT EXISTS (
            SELECT 1 
            FROM information_schema.columns c
            WHERE c.table_schema = 'public'
                AND c.table_name = t.table_name
                AND c.column_name = 'map_id'
        )
)
SELECT 
    COALESCE(q.table_name, m.table_name) AS table_name,
    CASE WHEN q.table_name IS NOT NULL THEN 'YES' ELSE 'NO' END AS needs_main_quadkey,
    CASE WHEN m.table_name IS NOT NULL THEN 'YES' ELSE 'NO' END AS needs_map_id
FROM tables_needing_quadkey q
FULL OUTER JOIN tables_needing_mapid m ON q.table_name = m.table_name
ORDER BY table_name;

\echo ''
\echo 'Existing foreign key constraints to signs table:'
\echo '------------------------------------------------'

SELECT
    tc.table_name,
    tc.constraint_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
    AND ccu.table_name = 'signs'
    AND tc.table_schema = 'public'
ORDER BY tc.table_name, kcu.column_name;

\echo ''
\echo 'Full schema of each referencing table:'
\echo '--------------------------------------'

\d+ alternating_lane_sign_association
\d+ dp_stop_point_group_to_tfl_associations
\d+ dp_stop_point_ra_association
\d+ dp_stop_point_sign_association
\d+ dp_stop_point_tlf_association
\d+ ltwa_dp_stop_point_to_tfl_association
\d+ sign_alternative_observation_associations
\d+ sign_supplementary_type_associations
\d+ sign_to_dp_association
\d+ sign_to_edge_association
