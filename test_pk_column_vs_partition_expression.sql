-- Test: Can we use column in PK but expression on that column in PARTITION BY?
-- Testing: PRIMARY KEY (id, main_quadkey, map_id) 
--          PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)

\echo '=========================================='
\echo 'TEST: PK on Column vs Expression in PARTITION'
\echo '=========================================='
\echo ''

-- ==================================================
-- TEST 1: Attempt the user's desired structure
-- ==================================================

\echo 'TEST 1: Creating table with PK on column, PARTITION BY expression'
\echo '-------------------------------------------------------------------'

DROP TABLE IF EXISTS test_pk_column_expr CASCADE;

\echo 'Attempting to create:'
\echo '  PRIMARY KEY (id, main_quadkey, map_id)'
\echo '  PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)'
\echo ''

-- This will either succeed or fail with an error
-- Error expected: "unique constraint on partitioned table must include all partitioning columns"

CREATE TABLE test_pk_column_expr (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,
    map_id INTEGER NOT NULL,
    data TEXT,
    PRIMARY KEY (id, main_quadkey, map_id)
) PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id);

\echo ''
\echo '✅ SUCCESS! PostgreSQL accepted this structure.'
\echo '   PK uses column, PARTITION uses expression.'
\echo ''

-- If we get here, create partitions and test
CREATE TABLE test_pk_column_expr_p0 PARTITION OF test_pk_column_expr
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE test_pk_column_expr_p1 PARTITION OF test_pk_column_expr
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE test_pk_column_expr_p2 PARTITION OF test_pk_column_expr
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE test_pk_column_expr_p3 PARTITION OF test_pk_column_expr
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);

\echo 'Partitions created successfully.'
\echo ''

-- Test data insertion
\echo 'Inserting test data...'
INSERT INTO test_pk_column_expr (id, main_quadkey, map_id, data)
VALUES 
    (1, 1656756156, 42, 'test1'),
    (2, 1656755952, 42, 'test2'),
    (3, 1656756136, 43, 'test3'),
    (4, 1656757568, 44, 'test4'),
    (5, 1656756999, 42, 'test5');  -- same FLOOR value as row 1

\echo '✅ Data inserted successfully.'
\echo ''

-- Show which partition each row went to
\echo 'Partition distribution:'
SELECT tableoid::regclass as partition, id, main_quadkey, map_id, FLOOR(main_quadkey / 1000) as quadkey_l12
FROM test_pk_column_expr
ORDER BY id;

\echo ''
\echo '================================================================='
\echo 'PARTITION PRUNING TESTS'
\echo '================================================================='
\echo ''

-- Test 1: Query by expression (matches partition key)
\echo 'Query 1: Filter by FLOOR(main_quadkey / 1000) and map_id (matches partition key)'
\echo '---------------------------------------------------------------------------------'
EXPLAIN (COSTS OFF, VERBOSE OFF)
SELECT * FROM test_pk_column_expr 
WHERE FLOOR(main_quadkey / 1000) = 1656756 
  AND map_id = 42;

\echo ''
\echo 'Expected: Should show selective partition scan (pruning works)'
\echo ''

-- Test 2: Query by column value (does NOT match partition key expression)
\echo 'Query 2: Filter by main_quadkey and map_id (NOT matching partition expression)'
\echo '-------------------------------------------------------------------------------'
EXPLAIN (COSTS OFF, VERBOSE OFF)
SELECT * FROM test_pk_column_expr 
WHERE main_quadkey = 1656756156 
  AND map_id = 42;

\echo ''
\echo 'Expected: May scan ALL partitions (no guaranteed pruning)'
\echo ''

-- Test 3: Query by both
\echo 'Query 3: Filter by BOTH main_quadkey AND expression'
\echo '----------------------------------------------------'
EXPLAIN (COSTS OFF, VERBOSE OFF)
SELECT * FROM test_pk_column_expr 
WHERE main_quadkey = 1656756156 
  AND FLOOR(main_quadkey / 1000) = 1656756
  AND map_id = 42;

\echo ''
\echo 'Expected: Should prune partitions (expression match)'
\echo ''

-- Test 4: Query by id (part of PK but not partition key)
\echo 'Query 4: Filter by id only'
\echo '---------------------------'
EXPLAIN (COSTS OFF, VERBOSE OFF)
SELECT * FROM test_pk_column_expr 
WHERE id = 1;

\echo ''
\echo 'Expected: Full scan of ALL partitions (no partition key in WHERE)'
\echo ''

-- Test 5: Range query on main_quadkey
\echo 'Query 5: Range query on main_quadkey'
\echo '-------------------------------------'
EXPLAIN (COSTS OFF, VERBOSE OFF)
SELECT * FROM test_pk_column_expr 
WHERE main_quadkey BETWEEN 1656756000 AND 1656756999
  AND map_id = 42;

\echo ''
\echo 'Expected: May or may not prune (depends on planner intelligence)'
\echo ''

\echo ''
\echo '================================================================='
\echo 'UNIQUENESS CONSTRAINT TESTS'
\echo '================================================================='
\echo ''

-- Test uniqueness: Can we insert duplicate id with different quadkey?
\echo 'Test 6: Attempting to insert duplicate id with different quadkey'
\echo '-----------------------------------------------------------------'
BEGIN;
INSERT INTO test_pk_column_expr (id, main_quadkey, map_id, data)
VALUES (1, 1656755000, 42, 'duplicate_id');  -- id=1 already exists
ROLLBACK;

\echo 'Expected: Should fail with PK violation'
\echo ''

-- Test uniqueness: Can we insert same id, quadkey, but different map_id?
\echo 'Test 7: Attempting to insert duplicate (id, quadkey) with different map_id'
\echo '---------------------------------------------------------------------------'
BEGIN;
INSERT INTO test_pk_column_expr (id, main_quadkey, map_id, data)
VALUES (1, 1656756156, 99, 'different_map');  -- id=1, quadkey matches row 1
ROLLBACK;

\echo 'Expected: Should fail with PK violation (PK is on all three columns)'
\echo ''

-- Test uniqueness: Can we insert different id, but same quadkey FLOOR?
\echo 'Test 8: Inserting different id, same FLOOR(quadkey/1000), same map_id'
\echo '----------------------------------------------------------------------'
BEGIN;
INSERT INTO test_pk_column_expr (id, main_quadkey, map_id, data)
VALUES (99, 1656756500, 42, 'same_floor_different_id');
-- FLOOR(1656756500/1000) = 1656756, same as row 1
SELECT * FROM test_pk_column_expr WHERE id IN (1, 99);
ROLLBACK;

\echo 'Expected: Should succeed (different id, different main_quadkey)'
\echo ''

\echo ''
\echo '================================================================='
\echo 'CONCLUSION'
\echo '================================================================='
\echo ''
\echo 'If this test succeeded, it means:'
\echo '  1. ✅ PostgreSQL DOES allow PK on column when PARTITION uses expression'
\echo '  2. ❓ Partition pruning may NOT work when querying by column value'
\echo '  3. ✅ Partition pruning WILL work when querying by expression'
\echo '  4. 💡 Application must use expression in WHERE for guaranteed pruning'
\echo ''
\echo 'Structure that works:'
\echo '  PRIMARY KEY (id, main_quadkey, map_id)'
\echo '  PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)'
\echo ''

-- Cleanup
DROP TABLE IF EXISTS test_pk_column_expr CASCADE;

\echo ''
\echo '=========================================='
\echo 'Test Complete'
\echo '=========================================='
