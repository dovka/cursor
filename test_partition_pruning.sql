-- Test Script: Partition Pruning with Expressions vs Stored Columns
-- Run this on a test database to understand partition pruning behavior

\echo '=========================================='
\echo 'TEST: Partition Pruning Analysis'
\echo '=========================================='
\echo ''

-- ==================================================
-- TEST 1: Expression in PARTITION BY
-- ==================================================

\echo 'TEST 1: Using Expression in PARTITION BY'
\echo '-----------------------------------------'

DROP TABLE IF EXISTS test_signs_expression CASCADE;

CREATE TABLE test_signs_expression (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,
    map_id INTEGER NOT NULL,
    data TEXT,
    -- PK with expression (required for partitioning by expression)
    PRIMARY KEY (id, (FLOOR(main_quadkey / 1000)), map_id)
) PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id);

-- Create 4 partitions for testing
CREATE TABLE test_signs_expression_p0 PARTITION OF test_signs_expression
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE test_signs_expression_p1 PARTITION OF test_signs_expression
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE test_signs_expression_p2 PARTITION OF test_signs_expression
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE test_signs_expression_p3 PARTITION OF test_signs_expression
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- Insert test data
INSERT INTO test_signs_expression (id, main_quadkey, map_id, data)
VALUES 
    (1, 1656756156, 42, 'test1'),
    (2, 1656755952, 42, 'test2'),
    (3, 1656756136, 43, 'test3'),
    (4, 1656757568, 44, 'test4');

\echo ''
\echo 'Query 1A: Filter by expression (matches partition key)'
EXPLAIN (COSTS OFF) 
SELECT * FROM test_signs_expression 
WHERE FLOOR(main_quadkey / 1000) = 1656756 
  AND map_id = 42;

\echo ''
\echo 'Query 1B: Filter by original main_quadkey value'
EXPLAIN (COSTS OFF)
SELECT * FROM test_signs_expression 
WHERE main_quadkey = 1656756156 
  AND map_id = 42;

\echo ''
\echo '==> Note: Check if Query 1B shows "Seq Scan on ALL partitions" or selective scan'
\echo ''

-- ==================================================
-- TEST 2: Stored Column Approach
-- ==================================================

\echo ''
\echo 'TEST 2: Using Stored Column for Level 12'
\echo '-----------------------------------------'

DROP TABLE IF EXISTS test_signs_stored CASCADE;

CREATE TABLE test_signs_stored (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,      -- level 15
    main_quadkey_l12 INTEGER NOT NULL,  -- level 12 (stored)
    map_id INTEGER NOT NULL,
    data TEXT,
    PRIMARY KEY (id, main_quadkey_l12, map_id)
) PARTITION BY HASH (main_quadkey_l12, map_id);

-- Create 4 partitions for testing
CREATE TABLE test_signs_stored_p0 PARTITION OF test_signs_stored
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE test_signs_stored_p1 PARTITION OF test_signs_stored
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE test_signs_stored_p2 PARTITION OF test_signs_stored
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE test_signs_stored_p3 PARTITION OF test_signs_stored
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- Insert test data with computed level 12
INSERT INTO test_signs_stored (id, main_quadkey, main_quadkey_l12, map_id, data)
VALUES 
    (1, 1656756156, FLOOR(1656756156 / 1000), 42, 'test1'),
    (2, 1656755952, FLOOR(1656755952 / 1000), 42, 'test2'),
    (3, 1656756136, FLOOR(1656756136 / 1000), 43, 'test3'),
    (4, 1656757568, FLOOR(1656757568 / 1000), 44, 'test4');

\echo ''
\echo 'Query 2A: Filter by level 12 column (matches partition key)'
EXPLAIN (COSTS OFF)
SELECT * FROM test_signs_stored 
WHERE main_quadkey_l12 = 1656756 
  AND map_id = 42;

\echo ''
\echo 'Query 2B: Filter by level 15 only (NO partition pruning expected)'
EXPLAIN (COSTS OFF)
SELECT * FROM test_signs_stored 
WHERE main_quadkey = 1656756156 
  AND map_id = 42;

\echo ''
\echo 'Query 2C: Filter by BOTH levels (WILL prune partitions)'
EXPLAIN (COSTS OFF)
SELECT * FROM test_signs_stored 
WHERE main_quadkey = 1656756156 
  AND main_quadkey_l12 = 1656756
  AND map_id = 42;

\echo ''
\echo '==> Note: Query 2C shows best of both worlds - accurate filtering + partition pruning'
\echo ''

-- ==================================================
-- TEST 3: Generated Column Approach (PostgreSQL 12+)
-- ==================================================

\echo ''
\echo 'TEST 3: Using Generated Column (PostgreSQL 12+)'
\echo '-----------------------------------------------'

-- Check PostgreSQL version
SELECT version();

DROP TABLE IF EXISTS test_signs_generated CASCADE;

CREATE TABLE test_signs_generated (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,      -- level 15
    main_quadkey_l12 INTEGER NOT NULL   -- level 12 (generated)
        GENERATED ALWAYS AS (FLOOR(main_quadkey / 1000)) STORED,
    map_id INTEGER NOT NULL,
    data TEXT,
    PRIMARY KEY (id, main_quadkey_l12, map_id)
) PARTITION BY HASH (main_quadkey_l12, map_id);

-- Create 4 partitions for testing
CREATE TABLE test_signs_generated_p0 PARTITION OF test_signs_generated
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE test_signs_generated_p1 PARTITION OF test_signs_generated
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE test_signs_generated_p2 PARTITION OF test_signs_generated
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE test_signs_generated_p3 PARTITION OF test_signs_generated
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- Insert test data (main_quadkey_l12 auto-computed)
INSERT INTO test_signs_generated (id, main_quadkey, map_id, data)
VALUES 
    (1, 1656756156, 42, 'test1'),
    (2, 1656755952, 42, 'test2'),
    (3, 1656756136, 43, 'test3'),
    (4, 1656757568, 44, 'test4');

\echo ''
\echo 'Query 3A: Filter by level 12 (partition pruning works)'
EXPLAIN (COSTS OFF)
SELECT * FROM test_signs_generated 
WHERE main_quadkey_l12 = 1656756 
  AND map_id = 42;

\echo ''
\echo 'Query 3B: Filter by level 15 (may or may not prune)'
EXPLAIN (COSTS OFF)
SELECT * FROM test_signs_generated 
WHERE main_quadkey = 1656756156 
  AND map_id = 42;

\echo ''
\echo '==> Generated columns auto-maintain level 12 value'
\echo ''

-- ==================================================
-- TEST 4: Verify Conversion Formula
-- ==================================================

\echo ''
\echo 'TEST 4: Verify Quadkey Conversion Formula'
\echo '------------------------------------------'

\echo ''
\echo 'Sample quadkey conversions (Level 15 → Level 12):'

SELECT 
    main_quadkey as level_15,
    FLOOR(main_quadkey / 1000) as level_12_div1000,
    main_quadkey >> 6 as level_12_bitshift,
    FLOOR(main_quadkey / 8) as level_12_div8,
    CAST(LEFT(main_quadkey::TEXT, LENGTH(main_quadkey::TEXT) - 3) AS INTEGER) as level_12_string_truncate
FROM test_signs_stored
ORDER BY main_quadkey;

\echo ''
\echo 'Explanation of conversion methods:'
\echo '  - div1000: FLOOR(main_quadkey / 1000) - removes last 3 decimal digits'
\echo '  - bitshift: main_quadkey >> 6 - removes last 6 bits (3 levels * 2 bits)'
\echo '  - div8: FLOOR(main_quadkey / 8) - divides by 2^3'
\echo '  - string_truncate: removes last 3 characters from string representation'
\echo ''
\echo 'Which conversion formula gives correct level 12 quadkeys?'
\echo ''

-- ==================================================
-- Cleanup
-- ==================================================

\echo ''
\echo 'Cleanup test tables:'
DROP TABLE IF EXISTS test_signs_expression CASCADE;
DROP TABLE IF EXISTS test_signs_stored CASCADE;
DROP TABLE IF EXISTS test_signs_generated CASCADE;

\echo ''
\echo '=========================================='
\echo 'Test Complete'
\echo '=========================================='
\echo ''
\echo 'Key Findings:'
\echo '1. Expression in PARTITION BY may not reliably prune when filtering by base column'
\echo '2. Stored column approach guarantees pruning when you filter by that column'
\echo '3. Generated columns (PG12+) automatically maintain computed values'
\echo '4. Best practice: Include partition key columns in WHERE clause for guaranteed pruning'
\echo ''
