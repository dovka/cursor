# How to Run the Signs Partitioning Test

## Purpose

This test validates your proposed partitioning structure using **real data** from your signs table:

```sql
PRIMARY KEY (id, main_quadkey, map_id)
PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)
```

## What the Test Does

1. ✅ Extracts 10,000 real rows from your signs table
2. ✅ Creates partitioned table with your proposed structure
3. ✅ Tests if PostgreSQL accepts PK on column with expression in PARTITION BY
4. ✅ Analyzes partition pruning behavior with various query patterns
5. ✅ Tests foreign key constraints
6. ✅ Validates quadkey conversion formula
7. ✅ Shows partition distribution of real data

## Prerequisites

- Access to your database with signs table
- The `basemapuuids_4_partition_qk` table exists and is accessible
- Sufficient permissions to CREATE and DROP tables

## How to Run

### Option 1: Run the entire test script

```bash
psql -d your_database_name -f test_signs_partitioning_real_data.sql
```

### Option 2: Run interactively

```bash
psql -d your_database_name

\i test_signs_partitioning_real_data.sql
```

### Option 3: Run with output saved to file

```bash
psql -d your_database_name -f test_signs_partitioning_real_data.sql | tee test_results.txt
```

## Expected Runtime

- Data extraction: ~1-5 seconds
- Table creation: < 1 second  
- Data loading: ~2-10 seconds
- Query tests: ~5-15 seconds
- **Total: ~10-30 seconds**

## Key Questions the Test Answers

### Question 1: Structure Validity ✅ or ❌

**Does PostgreSQL accept this structure?**
```sql
PRIMARY KEY (id, main_quadkey, map_id)
PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)
```

- ✅ If test succeeds: Structure is valid, proceed with this approach
- ❌ If test fails: Must use alternative (stored column or expression in PK)

### Question 2: Partition Pruning Behavior 🔍

**Critical Tests:**

| Test | Query Pattern | Expected Result | What It Means |
|------|---------------|-----------------|---------------|
| Test 1 | `WHERE FLOOR(main_quadkey/1000) = X AND map_id = Y` | ✅ Prunes | Expression-based queries are efficient |
| Test 2 | `WHERE main_quadkey = X AND map_id = Y` | ❓ Unknown | **MOST CRITICAL TEST** - does column query prune? |
| Test 3 | Both column + expression | ✅ Prunes | Redundant but guaranteed performance |
| Test 4 | `WHERE id = X` | ❌ No pruning | As expected - no partition key |

**Look for this in Test 2 output:**
```
Append (loops=1)
  ->  Seq Scan on signs_test_partitioned_p0
  ->  Seq Scan on signs_test_partitioned_p1
  ...
  ->  Seq Scan on signs_test_partitioned_p7
```

- If you see **ALL 8 partitions**: Pruning does NOT work with column-based queries
- If you see **1-2 partitions**: Pruning WORKS! Column-based queries are efficient

### Question 3: Quadkey Conversion Formula ❓

The test shows multiple conversion methods:
- `FLOOR(main_quadkey / 1000)` - Simple division
- `main_quadkey >> 6` - Bitwise shift
- Tile coordinate conversion
- Others

**You need to verify which formula is correct for your quadkey encoding!**

## How to Interpret Results

### Success Scenario ✅

```
✅ SUCCESS! PostgreSQL accepted the structure.
   PK uses columns: (id, main_quadkey, map_id)
   PARTITION uses expression: (FLOOR(main_quadkey / 1000), map_id)

Test 1: Scans 1 partition  ✅
Test 2: Scans 1 partition  ✅✅✅ BEST CASE!
```

**Interpretation:** Your structure works perfectly! Proceed with migration.

### Partial Success Scenario ⚠️

```
✅ SUCCESS! PostgreSQL accepted the structure.

Test 1: Scans 1 partition  ✅
Test 2: Scans ALL 8 partitions  ❌
Test 3: Scans 1 partition  ✅
```

**Interpretation:** Structure is valid, but partition pruning only works with expression in WHERE clause.

**Decision needed:**
- Accept this limitation (application must use expression in queries)
- Or use stored column approach for guaranteed pruning

### Failure Scenario ❌

```
ERROR: unique constraint on partitioned table must include all partitioning columns
```

**Interpretation:** PostgreSQL doesn't accept column in PK when partition uses expression.

**Solution:** Must use one of these alternatives:
1. `PRIMARY KEY (id, (FLOOR(main_quadkey/1000)), map_id)` - expression in PK
2. Add `main_quadkey_l12` column and use stored column approach

## After Running the Test

### 1. Review the Output

Pay special attention to:
- ✅ Did table creation succeed?
- 📊 Partition distribution (should be roughly even)
- 🔍 EXPLAIN outputs for Tests 1-6
- ❓ Quadkey conversion comparisons

### 2. Answer These Questions

**Q1:** Did PostgreSQL accept the structure?
- [ ] Yes, test succeeded
- [ ] No, got error

**Q2:** Does Test 2 (column-based query) prune partitions?
- [ ] Yes, scans 1-2 partitions (GREAT!)
- [ ] No, scans all partitions (application must use expression)
- [ ] Unsure (share EXPLAIN output)

**Q3:** Which quadkey conversion formula is correct?
- [ ] `FLOOR(main_quadkey / 1000)`
- [ ] `main_quadkey >> 6`
- [ ] Tile coordinate conversion
- [ ] Other: _______________
- [ ] Need to verify with team

**Q4:** Is partition distribution acceptable?
- [ ] Yes, roughly even across partitions
- [ ] No, too skewed (may need different partition key)

### 3. Share Results

If you need clarification, share:
1. Any errors encountered
2. EXPLAIN output from Test 2 (most critical)
3. Partition distribution summary
4. Sample quadkey conversion values

## Cleanup

After reviewing results, you can clean up test objects:

```sql
DROP TABLE IF EXISTS signs_test_partitioned CASCADE;
DROP TABLE IF EXISTS signs_test_data CASCADE;
DROP TABLE IF EXISTS test_referencing_table CASCADE;
```

Or keep them for further experimentation!

## Next Steps Based on Results

### If Test Fully Succeeds (Test 2 prunes)

✅ **Proceed with your proposed structure!**

I'll generate migration scripts with:
- `PRIMARY KEY (id, main_quadkey, map_id)`
- `PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)`
- 20 partitions
- All indexes including expression index
- FK updates for referencing tables

### If Test Partially Succeeds (Test 2 doesn't prune)

⚠️ **Decision needed:**

**Option A:** Accept limitation, use expression in queries
- Application must use: `WHERE FLOOR(main_quadkey/1000) = ? AND map_id = ?`
- Simpler schema, no column duplication

**Option B:** Use stored column approach
- Add `main_quadkey_l12` column
- Guaranteed pruning on column queries
- Slight storage overhead

### If Test Fails (Structure rejected)

❌ **Must use alternative approach**

Choose one:
1. Stored column: `main_quadkey_l12`
2. Expression in PK: `PRIMARY KEY (id, (FLOOR(...)), map_id)`

## Questions?

If you encounter unexpected results or need clarification:
1. Share the test output
2. Note which step failed or gave unexpected results
3. Share any error messages

---

**Ready to run the test!** This will give us definitive answers about whether your proposed structure works with real data.
