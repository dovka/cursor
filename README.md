# Aurora PostgreSQL Query Optimization - Force PK Index Usage

## Problem

Query with 436 quadkeys in an IN clause is not using the primary key `edge_quadkey_association_pkey (quadkey, edge_id)`. Instead, PostgreSQL scans the `edge_id` range and filters quadkeys, taking 17.5 seconds.

## Solution

Rewrite the query to use `unnest()` which forces PostgreSQL to use the primary key index for direct lookups.

**Expected speedup: 10-20x faster** (from 17.5s to <1s)

## Quick Start

1. **Read the solution summary:**
   ```bash
   cat SOLUTION_SUMMARY.md
   ```

2. **Run the optimized query:**
   ```bash
   psql -f optimized_query.sql
   ```

3. **Compare performance:**
   ```bash
   psql -f performance_comparison.sql
   ```

## Files in this Repository

| File | Description |
|------|-------------|
| `SOLUTION_SUMMARY.md` | Quick explanation of the problem and fix |
| `VISUAL_EXPLANATION.md` | Visual diagrams showing why the original is slow |
| `query_analysis.md` | Detailed technical analysis with multiple solutions |
| `optimized_query.sql` | Ready-to-run optimized query (uses PK index) |
| `performance_comparison.sql` | Side-by-side comparison of original vs optimized |

## Key Changes

### Before (Slow - 17.5s)
```sql
WHERE edge_quadkey_association.quadkey IN (436 values...)
  AND edge_id >= 122563426 AND edge_id < 123688919
```

**Problem:** Scans edge_id index → filters 42K rows by quadkey

### After (Fast - <1s)
```sql
FROM unnest(ARRAY[...436 values...]) AS quadkey_list(quadkey)
JOIN edge_quadkey_association 
  ON edge_quadkey_association.quadkey = quadkey_list.quadkey
  AND edge_quadkey_association.edge_id >= X AND edge_quadkey_association.edge_id < Y
```

**Solution:** 436 PK lookups → directly filtered by edge_id range

## Why This Works

The primary key `(quadkey, edge_id)` is a composite index:
- Organized first by `quadkey`, then by `edge_id` within each quadkey
- Perfect for looking up specific quadkeys and filtering by edge_id
- Original query structure prevented the planner from choosing this optimal path

The `unnest()` rewrite makes quadkeys the "driving table", forcing PostgreSQL to:
1. Loop through each of the 436 quadkeys
2. Do a direct PK lookup for each quadkey
3. Filter by edge_id range during the index scan (very fast)
4. Join to lanes table with minimal rows

## Verification

After running the optimized query, look for this in the EXPLAIN output:

✅ **Good:** `Index Scan using edge_quadkey_association_pkey`

❌ **Bad:** `Parallel Index Scan using ix_edge_quadkey_association_edge_id`

## Additional Resources

- Full technical analysis: `query_analysis.md`
- Alternative approaches and planner tuning options included
- Statistics and index health checks provided

## Questions?

The core issue is that PostgreSQL's cost-based optimizer made the wrong choice. By restructuring the query, we guide it to the optimal execution plan without changing the query logic or results.
