# Quick Solution Summary

## Why PK Index is Not Being Used

Your primary key `edge_quadkey_association_pkey (quadkey, edge_id)` is **not being used** because:

1. **You have 436 quadkeys in the IN clause** - The planner thinks 436 separate index lookups is expensive
2. **You have a range filter on edge_id** - This makes the planner prefer scanning the `ix_edge_quadkey_association_edge_id` index
3. **Planner chooses**: Scan edge_id range (42K rows) → Filter by quadkeys → Join to lanes

**This is backwards from what you want!**

## The Fix: Rewrite the Query

Change from:
```sql
WHERE edge_quadkey_association.quadkey IN (436 values...)
  AND edge_id >= X AND edge_id < Y
```

To:
```sql
FROM unnest(ARRAY[...436 values...]) AS quadkey_list(quadkey)
JOIN edge_quadkey_association ON edge_quadkey_association.quadkey = quadkey_list.quadkey
  AND edge_quadkey_association.edge_id >= X 
  AND edge_quadkey_association.edge_id < Y
```

## Why This Works

1. **Forces quadkeys as the driving table** - Makes PostgreSQL do 436 PK lookups
2. **Each PK lookup is filtered by edge_id immediately** - Uses the (quadkey, edge_id) composite index optimally
3. **Much fewer rows** passed to the lanes join
4. **Predictable performance** - Not subject to planner estimation errors

## Expected Performance Improvement

- **Current**: 17.5 seconds
- **Expected**: <1 second (10-20x faster)

## Action Items

1. **Run the optimized query** in `/workspace/optimized_query.sql`
2. **Check the EXPLAIN output** - Look for:
   - `Index Scan using edge_quadkey_association_pkey` ✅
   - NOT `Parallel Index Scan using ix_edge_quadkey_association_edge_id` ❌
3. **Compare execution times**

## Additional Tuning (If Needed)

If the rewrite still doesn't use the PK:

```sql
-- Option 1: Disable the edge_id index temporarily
SET LOCAL enable_bitmapscan = OFF;
-- Run your query

-- Option 2: Lower random_page_cost (makes index scans cheaper)
SET random_page_cost = 1.1;

-- Option 3: Update statistics
ANALYZE edge_quadkey_association;
ANALYZE lanes;
```

## Root Cause

The PostgreSQL query planner uses **cost-based optimization**. With your original query structure:

- Cost of scanning edge_id range: ~42K rows
- Cost of 436 PK lookups: 436 × estimated_rows_per_quadkey

The planner **estimated wrong** and chose the edge_id scan. By restructuring the query with `unnest()`, you force it to use the PK.

## Key Insight

**A composite index (quadkey, edge_id) is most efficient when:**
- You provide the **first column** (quadkey) as an equality condition
- You can filter the **second column** (edge_id) during the index scan

Your original query structure prevented this optimization. The rewrite enables it.
