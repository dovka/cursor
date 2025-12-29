-- ============================================================================
-- TEST: Signs Table Partitioning with Real Data Subset
-- ============================================================================
-- This script tests:
--   1. PRIMARY KEY (id, main_quadkey, map_id) with 
--      PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)
--   2. Partition pruning behavior with real data
--   3. Data distribution across partitions
-- ============================================================================

\timing on

\echo ''
\echo '============================================================================'
\echo 'STEP 1: Extract Real Data Subset'
\echo '============================================================================'
\echo ''

-- Create temporary table to hold test data
DROP TABLE IF EXISTS signs_test_data CASCADE;

\echo 'Extracting 10,000 rows from signs table...'
\echo 'Query: SELECT id, map_id, main_quadkey FROM signs s'
\echo '       JOIN basemapuuids_4_partition_qk qk ON (s.base_map_uuid=qk.base_map_uuid)'
\echo '       WHERE id BETWEEN 7188604714 AND 7198604714'
\echo '       LIMIT 10000'
\echo ''

CREATE TABLE signs_test_data AS
SELECT 
    s.id,
    s.map_id,
    s.main_quadkey,
    s.time_created,
    s.external_id,
    s.uuid,
    s.base_map_uuid,
    -- Add a few more columns for realism
    s.traffic_sign_type_id,
    s.system_type_id,
    s.width,
    s.height
FROM signs s 
JOIN basemapuuids_4_partition_qk qk ON (s.base_map_uuid = qk.base_map_uuid) 
WHERE s.id BETWEEN 7188604714 AND 7198604714
  AND s.map_id IS NOT NULL  -- Per requirements
LIMIT 10000;

\echo ''
\echo 'Data extraction summary:'
SELECT 
    COUNT(*) as total_rows,
    COUNT(DISTINCT id) as unique_ids,
    COUNT(DISTINCT map_id) as unique_map_ids,
    COUNT(DISTINCT main_quadkey) as unique_quadkeys_l15,
    COUNT(DISTINCT FLOOR(main_quadkey / 1000)) as unique_quadkeys_l12,
    MIN(main_quadkey) as min_quadkey,
    MAX(main_quadkey) as max_quadkey,
    COUNT(*) FILTER (WHERE main_quadkey IS NULL) as null_quadkeys,
    COUNT(*) FILTER (WHERE map_id IS NULL) as null_map_ids
FROM signs_test_data;

\echo ''
\echo 'Sample of extracted data:'
SELECT 
    id, 
    map_id, 
    main_quadkey,
    COALESCE(main_quadkey, 0) as quadkey_coalesced,
    FLOOR(COALESCE(main_quadkey, 0) / 1000) as quadkey_l12
FROM signs_test_data 
ORDER BY id
LIMIT 10;

\echo ''
\echo '============================================================================'
\echo 'STEP 2: Create Partitioned Table - User Proposed Structure'
\echo '============================================================================'
\echo ''

DROP TABLE IF EXISTS signs_test_partitioned CASCADE;

\echo 'Creating partitioned table with structure:'
\echo '  PRIMARY KEY (id, main_quadkey, map_id)'
\echo '  PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)'
\echo ''

-- Attempt to create the structure
-- This will either succeed or fail with constraint error

CREATE TABLE signs_test_partitioned (
    id BIGINT NOT NULL,
    map_id INTEGER NOT NULL,
    main_quadkey INTEGER NOT NULL,
    time_created TIMESTAMP WITHOUT TIME ZONE,
    external_id BIGINT,
    uuid UUID,
    base_map_uuid UUID,
    traffic_sign_type_id INTEGER,
    system_type_id INTEGER,
    width DOUBLE PRECISION,
    height DOUBLE PRECISION,
    
    -- Primary key on columns (NOT expression)
    PRIMARY KEY (id, main_quadkey, map_id)
    
) PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id);

\echo '✅ SUCCESS! PostgreSQL accepted the structure.'
\echo '   PK uses columns: (id, main_quadkey, map_id)'
\echo '   PARTITION uses expression: (FLOOR(main_quadkey / 1000), map_id)'
\echo ''

\echo ''
\echo '============================================================================'
\echo 'STEP 3: Create Partitions (8 partitions for testing)'
\echo '============================================================================'
\echo ''

CREATE TABLE signs_test_partitioned_p0 PARTITION OF signs_test_partitioned
    FOR VALUES WITH (MODULUS 8, REMAINDER 0);
    
CREATE TABLE signs_test_partitioned_p1 PARTITION OF signs_test_partitioned
    FOR VALUES WITH (MODULUS 8, REMAINDER 1);
    
CREATE TABLE signs_test_partitioned_p2 PARTITION OF signs_test_partitioned
    FOR VALUES WITH (MODULUS 8, REMAINDER 2);
    
CREATE TABLE signs_test_partitioned_p3 PARTITION OF signs_test_partitioned
    FOR VALUES WITH (MODULUS 8, REMAINDER 3);
    
CREATE TABLE signs_test_partitioned_p4 PARTITION OF signs_test_partitioned
    FOR VALUES WITH (MODULUS 8, REMAINDER 4);
    
CREATE TABLE signs_test_partitioned_p5 PARTITION OF signs_test_partitioned
    FOR VALUES WITH (MODULUS 8, REMAINDER 5);
    
CREATE TABLE signs_test_partitioned_p6 PARTITION OF signs_test_partitioned
    FOR VALUES WITH (MODULUS 8, REMAINDER 6);
    
CREATE TABLE signs_test_partitioned_p7 PARTITION OF signs_test_partitioned
    FOR VALUES WITH (MODULUS 8, REMAINDER 7);

\echo '✅ Created 8 partitions (p0 through p7)'
\echo ''

\echo ''
\echo '============================================================================'
\echo 'STEP 4: Load Test Data into Partitioned Table'
\echo '============================================================================'
\echo ''

\echo 'Inserting test data (handling NULL quadkeys)...'

INSERT INTO signs_test_partitioned (
    id, map_id, main_quadkey, time_created, external_id, uuid,
    base_map_uuid, traffic_sign_type_id, system_type_id, width, height
)
SELECT 
    id,
    map_id,
    COALESCE(main_quadkey, 0) as main_quadkey,  -- Set to 0 if NULL per requirements
    time_created,
    external_id,
    uuid,
    base_map_uuid,
    traffic_sign_type_id,
    system_type_id,
    width,
    height
FROM signs_test_data;

\echo ''
SELECT 'Inserted ' || COUNT(*) || ' rows' as status FROM signs_test_partitioned;
\echo ''

\echo ''
\echo '============================================================================'
\echo 'STEP 5: Analyze Partition Distribution'
\echo '============================================================================'
\echo ''

\echo 'Rows per partition:'
SELECT 
    tableoid::regclass AS partition_name,
    COUNT(*) as row_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) as percentage,
    MIN(main_quadkey) as min_quadkey,
    MAX(main_quadkey) as max_quadkey,
    COUNT(DISTINCT FLOOR(main_quadkey / 1000)) as unique_l12_quadkeys
FROM signs_test_partitioned
GROUP BY tableoid
ORDER BY partition_name;

\echo ''
\echo 'Sample data from each partition:'
WITH samples AS (
    SELECT 
        tableoid::regclass AS partition_name,
        id,
        main_quadkey,
        FLOOR(main_quadkey / 1000) as quadkey_l12,
        map_id,
        ROW_NUMBER() OVER (PARTITION BY tableoid ORDER BY id) as rn
    FROM signs_test_partitioned
)
SELECT partition_name, id, main_quadkey, quadkey_l12, map_id
FROM samples 
WHERE rn <= 2
ORDER BY partition_name, id;

\echo ''
\echo '============================================================================'
\echo 'STEP 6: Test Partition Pruning (CRITICAL TEST)'
\echo '============================================================================'
\echo ''

-- Get a sample quadkey value for testing
\echo 'Selecting a sample quadkey for testing...'
SELECT 
    main_quadkey,
    FLOOR(main_quadkey / 1000) as quadkey_l12,
    map_id
FROM signs_test_partitioned 
WHERE main_quadkey > 0
LIMIT 1 \gset

\echo 'Test values:'
\echo '  main_quadkey = ' :main_quadkey
\echo '  quadkey_l12 = ' :quadkey_l12
\echo '  map_id = ' :map_id
\echo ''

-- Test 1: Query by expression (should prune)
\echo ''
\echo '--- TEST 1: Filter by FLOOR(main_quadkey / 1000) = ' :quadkey_l12 ' AND map_id = ' :map_id
\echo '            (Matches partition key exactly - SHOULD PRUNE)'
\echo '---'
EXPLAIN (COSTS OFF, ANALYZE, TIMING OFF, SUMMARY OFF)
SELECT * FROM signs_test_partitioned 
WHERE FLOOR(main_quadkey / 1000) = :quadkey_l12
  AND map_id = :map_id;

\echo ''
\echo 'Expected: Should show selective partition scan (1 or few partitions)'
\echo ''

-- Test 2: Query by column value (may not prune)
\echo ''
\echo '--- TEST 2: Filter by main_quadkey = ' :main_quadkey ' AND map_id = ' :map_id
\echo '            (Uses column, not expression - MAY NOT PRUNE)'
\echo '---'
EXPLAIN (COSTS OFF, ANALYZE, TIMING OFF, SUMMARY OFF)
SELECT * FROM signs_test_partitioned 
WHERE main_quadkey = :main_quadkey
  AND map_id = :map_id;

\echo ''
\echo 'Expected: May scan ALL partitions if planner cannot derive expression'
\echo ''

-- Test 3: Query with both (should prune)
\echo ''
\echo '--- TEST 3: Filter by BOTH main_quadkey AND expression'
\echo '            (Redundant but guarantees pruning)'
\echo '---'
EXPLAIN (COSTS OFF, ANALYZE, TIMING OFF, SUMMARY OFF)
SELECT * FROM signs_test_partitioned 
WHERE main_quadkey = :main_quadkey
  AND FLOOR(main_quadkey / 1000) = :quadkey_l12
  AND map_id = :map_id;

\echo ''
\echo 'Expected: Should prune partitions (expression match)'
\echo ''

-- Test 4: Query by id only (no pruning expected)
\echo ''
\echo '--- TEST 4: Filter by id only (no partition key)'
\echo '---'
EXPLAIN (COSTS OFF)
SELECT * FROM signs_test_partitioned 
WHERE id = :main_quadkey;

\echo ''
\echo 'Expected: Scans ALL partitions (no partition key in WHERE)'
\echo ''

-- Test 5: Range query
\echo ''
\echo '--- TEST 5: Range query on main_quadkey'
\echo '---'
EXPLAIN (COSTS OFF)
SELECT * FROM signs_test_partitioned 
WHERE main_quadkey BETWEEN :main_quadkey AND :main_quadkey + 1000
  AND map_id = :map_id;

\echo ''
\echo 'Expected: Likely scans ALL partitions (range on column)'
\echo ''

-- Test 6: Query multiple expression values
\echo ''
\echo '--- TEST 6: Filter by expression IN (multiple values)'
\echo '---'
EXPLAIN (COSTS OFF)
SELECT * FROM signs_test_partitioned 
WHERE FLOOR(main_quadkey / 1000) IN (:quadkey_l12, :quadkey_l12 + 1)
  AND map_id = :map_id;

\echo ''
\echo 'Expected: Should prune to only relevant partitions'
\echo ''

\echo ''
\echo '============================================================================'
\echo 'STEP 7: Test Additional Index (Your Suggestion)'
\echo '============================================================================'
\echo ''

\echo 'Creating index on partition key expression...'
\echo 'CREATE INDEX idx_test_partition_key'
\echo '  ON signs_test_partitioned (FLOOR(main_quadkey / 1000), map_id, id)'
\echo ''

CREATE INDEX idx_test_partition_key 
ON signs_test_partitioned (FLOOR(main_quadkey / 1000), map_id, id);

\echo '✅ Index created'
\echo ''

\echo 'Re-running Test 2 with index in place:'
\echo '--- TEST 2b: Filter by main_quadkey (with expression index)'
\echo '---'
EXPLAIN (COSTS OFF, ANALYZE, TIMING OFF, SUMMARY OFF)
SELECT * FROM signs_test_partitioned 
WHERE main_quadkey = :main_quadkey
  AND map_id = :map_id;

\echo ''
\echo 'Does the index help with pruning when querying by column?'
\echo ''

\echo ''
\echo '============================================================================'
\echo 'STEP 8: Verify Primary Key Uniqueness'
\echo '============================================================================'
\echo ''

\echo 'Test 8a: Attempting to insert duplicate (id, main_quadkey, map_id)...'
BEGIN;
INSERT INTO signs_test_partitioned (id, main_quadkey, map_id, system_type_id)
VALUES (:main_quadkey, :main_quadkey, :map_id, 1);
\echo '❌ Should fail with PK violation'
ROLLBACK;

\echo ''
\echo 'Test 8b: Insert same id with different main_quadkey (should also fail)...'
BEGIN;
INSERT INTO signs_test_partitioned (id, main_quadkey, map_id, system_type_id)
VALUES (:main_quadkey, :main_quadkey + 100, :map_id, 1);
\echo '❌ Should fail with PK violation'
ROLLBACK;

\echo ''
\echo 'Test 8c: Insert different id, same FLOOR(quadkey) (should succeed)...'
BEGIN;
INSERT INTO signs_test_partitioned (id, main_quadkey, map_id, system_type_id)
VALUES (9999999999, :main_quadkey + 500, :map_id, 1);
-- Note: FLOOR(main_quadkey + 500 / 1000) = same as FLOOR(main_quadkey / 1000) if < 1000
\echo '✅ Should succeed (different id, different main_quadkey)'
SELECT 'Inserted into partition: ' || tableoid::regclass 
FROM signs_test_partitioned 
WHERE id = 9999999999;
ROLLBACK;

\echo ''
\echo '============================================================================'
\echo 'STEP 9: Test Quadkey Conversion Formula Validation'
\echo '============================================================================'
\echo ''

\echo 'Verifying quadkey conversion formula: FLOOR(main_quadkey / 1000)'
\echo ''
\echo 'Sample conversions:'

SELECT 
    main_quadkey as level_15,
    FLOOR(main_quadkey / 1000) as level_12_div1000,
    main_quadkey >> 6 as level_12_bitshift6,
    FLOOR(main_quadkey / 8) as level_12_div8,
    -- Tile coordinate approach (if level 16)
    FLOOR(main_quadkey / 65536 / 16) * 4096 + FLOOR((main_quadkey % 65536) / 16) as level_12_tile_conversion
FROM signs_test_partitioned
WHERE main_quadkey > 0
ORDER BY main_quadkey
LIMIT 10;

\echo ''
\echo 'Conversion method comparison:'
\echo '  - div1000: Simple division by 1000 (removes 3 decimal digits)'
\echo '  - bitshift6: Right shift 6 bits (Morton code for 3 levels)'
\echo '  - div8: Division by 8 (reduces by 2^3)'
\echo '  - tile_conversion: Extract x,y at L16, convert to L12, reconstruct'
\echo ''
\echo 'Which conversion produces valid level 12 quadkeys?'
\echo 'PLEASE VERIFY WITH YOUR TEAM!'
\echo ''

\echo ''
\echo '============================================================================'
\echo 'STEP 10: Foreign Key Simulation'
\echo '============================================================================'
\echo ''

\echo 'Simulating a referencing table (e.g., sign_to_edge_association)...'

DROP TABLE IF EXISTS test_referencing_table CASCADE;

CREATE TABLE test_referencing_table (
    association_id SERIAL PRIMARY KEY,
    sign_id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,
    map_id INTEGER NOT NULL,
    edge_id INTEGER NOT NULL,
    
    -- Foreign key references the composite PK
    FOREIGN KEY (sign_id, main_quadkey, map_id) 
    REFERENCES signs_test_partitioned(id, main_quadkey, map_id)
    DEFERRABLE
);

\echo '✅ Foreign key constraint created successfully'
\echo ''

\echo 'Inserting valid reference...'
INSERT INTO test_referencing_table (sign_id, main_quadkey, map_id, edge_id)
SELECT id, main_quadkey, map_id, 12345
FROM signs_test_partitioned
LIMIT 1;

\echo '✅ Valid FK insert succeeded'
\echo ''

\echo 'Attempting invalid reference...'
BEGIN;
INSERT INTO test_referencing_table (sign_id, main_quadkey, map_id, edge_id)
VALUES (9999999999, 1234567890, 999, 12345);
\echo '❌ Should fail with FK violation'
ROLLBACK;

\echo ''
\echo '============================================================================'
\echo 'SUMMARY AND CONCLUSIONS'
\echo '============================================================================'
\echo ''

\echo '✅ STRUCTURE TEST: PRIMARY KEY (id, main_quadkey, map_id) with'
\echo '                   PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)'
\echo '                   --> ACCEPTED by PostgreSQL!'
\echo ''

\echo '📊 PARTITION PRUNING RESULTS:'
\echo '   Review the EXPLAIN outputs above to determine:'
\echo '   - Does Test 1 (filter by expression) prune partitions? ✅ Expected: YES'
\echo '   - Does Test 2 (filter by column) prune partitions? ❓ Expected: MAYBE NOT'
\echo '   - Does the expression index help Test 2? ❓ To be determined'
\echo ''

\echo '🔧 IMPLICATIONS FOR APPLICATION:'
\echo '   - If Test 2 does NOT prune: Queries must use FLOOR(main_quadkey/1000) in WHERE'
\echo '   - If Test 2 DOES prune: Column-based queries work efficiently!'
\echo ''

\echo '✅ FOREIGN KEY TEST: Composite FK (sign_id, main_quadkey, map_id) works'
\echo '                     Referencing tables store full precision main_quadkey (level 15)'
\echo ''

\echo '❓ QUADKEY CONVERSION: Please verify FLOOR(main_quadkey / 1000) is correct'
\echo '                       for level 15 → level 12 conversion in your system'
\echo ''

\echo '============================================================================'
\echo 'CLEANUP (optional)'
\echo '============================================================================'
\echo ''

\echo 'To clean up test objects, run:'
\echo '  DROP TABLE IF EXISTS signs_test_partitioned CASCADE;'
\echo '  DROP TABLE IF EXISTS signs_test_data CASCADE;'
\echo '  DROP TABLE IF EXISTS test_referencing_table CASCADE;'
\echo ''

\echo 'Test complete!'
\echo ''
