# Aurora PostgreSQL Query Tuning Analysis

## Problem Summary

The query is not using the primary key `edge_quadkey_association_pkey (quadkey, edge_id)` and instead:
1. Uses `ix_edge_quadkey_association_edge_id` for range scan on `edge_id`
2. Filters the 436 quadkeys AFTER the index scan (as a Filter operation)
3. Results in scanning ~42,000 rows to filter down to the matching quadkeys

## Why the PK is Not Being Used

The PostgreSQL query planner chose the edge_id index because:

1. **Cost Estimation**: With 436 quadkeys, using the PK would require 436 separate index lookups
2. **Range Condition**: The `edge_id >= 122563426 AND edge_id < 123688919` is a range, making it less selective when combined with IN clause
3. **Statistics**: The planner estimates scanning edge_id range + filtering quadkeys is cheaper than 436 PK lookups

## Current Query Pattern
```sql
WHERE edge_quadkey_association.quadkey IN (436 values...)
  AND edge_id >= 122563426 AND edge_id < 123688919
```

This forces the planner to choose between:
- Option A: Scan quadkeys (436 PK lookups) → filter by edge_id range
- Option B: Scan edge_id range → filter by quadkeys (CHOSEN)

The planner chose Option B because it estimated fewer rows in the edge_id range.

## Solutions

### Solution 1: Rewrite with VALUES/UNNEST (RECOMMENDED)

This makes the quadkey list the driving table and forces PK usage:

```sql
SELECT lanes.id AS __id
FROM unnest(ARRAY[
    '122112223301031', '122112223321320', '122112223302123', 
    -- ... all 436 quadkeys
    '122112223303010'
]::varchar[]) AS quadkey_list(quadkey)
JOIN edge_quadkey_association eqa 
    ON eqa.quadkey = quadkey_list.quadkey
    AND eqa.edge_id >= 122563426 
    AND eqa.edge_id < 123688919
JOIN lanes 
    ON eqa.edge_id = lanes.edge_id
    AND lanes.base_map_uuid = '11f280b5-8595-471d-ad69-88bbea54735a'::UUID
WHERE lanes.id IS NOT NULL;
```

### Solution 2: Use CTE to Materialize Quadkeys

```sql
WITH quadkey_filter AS (
    SELECT unnest(ARRAY[
        '122112223301031', '122112223321320', '122112223302123',
        -- ... all quadkeys
        '122112223303010'
    ]::varchar[]) AS quadkey
)
SELECT lanes.id AS __id
FROM quadkey_filter qf
JOIN edge_quadkey_association eqa 
    ON eqa.quadkey = qf.quadkey
    AND eqa.edge_id >= 122563426 
    AND eqa.edge_id < 123688919
JOIN lanes 
    ON eqa.edge_id = lanes.edge_id
    AND lanes.base_map_uuid = '11f280b5-8595-471d-ad69-88bbea54735a'::UUID
WHERE lanes.id IS NOT NULL;
```

### Solution 3: Split into Two Separate Filters (Union)

If the quadkey list represents distinct spatial regions:

```sql
-- First get by quadkeys (uses PK)
SELECT lanes.id AS __id
FROM edge_quadkey_association eqa
JOIN lanes ON eqa.edge_id = lanes.edge_id
WHERE eqa.quadkey = ANY(ARRAY['122112223301031', ...])
  AND lanes.base_map_uuid = '11f280b5-8595-471d-ad69-88bbea54735a'::UUID
  AND lanes.id IS NOT NULL
  AND eqa.edge_id >= 122563426 
  AND eqa.edge_id < 123688919;
```

### Solution 4: Adjust Planner Settings (Temporary)

Force the planner to prefer index scans:

```sql
SET LOCAL enable_seqscan = OFF;
SET LOCAL random_page_cost = 1.1;  -- Lower to prefer index
SET LOCAL cpu_tuple_cost = 0.1;    -- Increase to discourage filtering

-- Your original query here
```

### Solution 5: Create a Covering Index

If this query pattern is common:

```sql
CREATE INDEX idx_quadkey_edge_covering 
ON edge_quadkey_association (quadkey, edge_id) 
INCLUDE (last_run_uuid, map_id);  -- If needed by other queries
```

## Recommended Approach

**Use Solution 1** (UNNEST rewrite) because:
- Forces the planner to use the PK index efficiently
- Makes the query plan predictable
- Should reduce execution time significantly (from 17s to <1s expected)
- Works with Aurora PostgreSQL without configuration changes

### Expected Performance

With PK usage:
- 436 index lookups on `(quadkey, edge_id)` → highly selective
- Each lookup filters by edge_id range immediately
- Much fewer rows passed to the lanes join
- **Expected: <1 second** (vs current 17.5 seconds)

## Additional Optimizations

1. **Analyze Statistics**: Ensure statistics are up-to-date
```sql
ANALYZE edge_quadkey_association;
ANALYZE lanes;
```

2. **Check Index Bloat**: 
```sql
SELECT schemaname, tablename, 
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables 
WHERE tablename = 'edge_quadkey_association';
```

3. **Consider Partitioning**: If edge_id ranges are predictable, partition by edge_id range

4. **Vacuum**: Ensure tables are vacuumed regularly
```sql
VACUUM ANALYZE edge_quadkey_association;
```
