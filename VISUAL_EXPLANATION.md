# Visual Explanation: Why Your Query is Slow

## The Problem in Pictures

### Your Composite Primary Key Structure

```
edge_quadkey_association_pkey: (quadkey, edge_id)

Physical Index Organization:
┌─────────────────┬──────────┐
│ quadkey         │ edge_id  │
├─────────────────┼──────────┤
│ 122112223123200 │  1000000 │
│ 122112223123200 │  1000523 │
│ 122112223123200 │  1002341 │
│ 122112223123202 │  2000123 │
│ 122112223123202 │  2000456 │
│ 122112223123213 │  3000789 │
│ ...             │  ...     │
└─────────────────┴──────────┘
```

**Key Insight:** Index is sorted by quadkey FIRST, then edge_id within each quadkey.

## Original Query Execution Plan (SLOW)

### What You Wrote:
```sql
WHERE quadkey IN (436 values...)
  AND edge_id >= 122563426 AND edge_id < 123688919
```

### What PostgreSQL Did:

```
Step 1: Scan ix_edge_quadkey_association_edge_id
        ↓
   ┌────────────────────────────────────┐
   │ edge_id >= 122563426               │
   │ edge_id < 123688919                │
   │                                     │
   │ Result: ~42,000 rows per worker    │
   └────────────────────────────────────┘
        ↓
Step 2: Filter by quadkey IN (...)
        ↓
   ┌────────────────────────────────────┐
   │ Check if quadkey matches any       │
   │ of the 436 values                  │
   │                                     │
   │ Scans ~42,000 rows!                │
   └────────────────────────────────────┘
        ↓
Step 3: Join to lanes
        ↓
   Result: Much work, slow performance
```

**Time: 17.5 seconds**

### Why This Happens:

PostgreSQL's planner thought:
- "I need to find rows matching 436 different quadkeys AND an edge_id range"
- "Option A: Do 436 index lookups on the PK"
- "Option B: Scan the edge_id range (estimated ~42K rows) and filter"
- "I estimate Option B is cheaper" ← **WRONG CHOICE!**

## Optimized Query Execution Plan (FAST)

### What You Should Write:
```sql
FROM unnest(ARRAY[...436 values...]) AS quadkey_list(quadkey)
JOIN edge_quadkey_association 
  ON edge_quadkey_association.quadkey = quadkey_list.quadkey
  AND edge_quadkey_association.edge_id >= 122563426
  AND edge_quadkey_association.edge_id < 123688919
```

### What PostgreSQL Does:

```
Step 1: Create virtual table of 436 quadkeys
        ↓
   ┌─────────────────┐
   │ 122112223301031 │
   │ 122112223321320 │
   │ 122112223302123 │
   │ ...             │
   │ (436 rows)      │
   └─────────────────┘
        ↓
Step 2: For EACH quadkey, do a PK lookup
        ↓
   Loop iteration 1:
   ┌────────────────────────────────────┐
   │ PK lookup: quadkey = '122112223301031' │
   │   AND edge_id >= 122563426         │
   │   AND edge_id < 123688919          │
   │                                     │
   │ Uses PK index directly!            │
   │ Result: 0-10 rows (highly selective)│
   └────────────────────────────────────┘
        ↓
   Loop iteration 2:
   ┌────────────────────────────────────┐
   │ PK lookup: quadkey = '122112223321320' │
   │   AND edge_id >= 122563426         │
   │   AND edge_id < 123688919          │
   │                                     │
   │ Uses PK index directly!            │
   │ Result: 0-10 rows (highly selective)│
   └────────────────────────────────────┘
        ↓
   ... (434 more iterations)
        ↓
Step 3: Join to lanes (with minimal rows)
        ↓
   Result: Fast, predictable performance
```

**Time: <1 second**

### Why This Works:

- **436 PK lookups** is actually CHEAP because:
  - Each lookup is O(log n) on the index
  - The index is perfectly organized for this (quadkey is first column)
  - Each lookup is highly selective (returns 0-10 rows per quadkey)
  
- **Total rows scanned**: ~436-4360 rows (vs 42,000+ in original)
- **No filtering needed**: Rows match immediately

## The Math

### Original Approach:
```
Cost = Scan edge_id range + Filter quadkeys
     = 42,000 rows × (cost per row) × 2 workers
     = EXPENSIVE
```

### Optimized Approach:
```
Cost = 436 PK lookups × (0-10 rows each)
     = 436 × 5 (average) = ~2,180 rows
     = CHEAP
```

**Speedup: 42,000 / 2,180 = ~19x fewer rows processed**

## Key Takeaway

**Composite indexes are ordered!**

- PK `(quadkey, edge_id)` is perfect for: "Give me rows where quadkey = X AND edge_id in range Y-Z"
- PK `(quadkey, edge_id)` is NOT used well for: "Give me rows where edge_id in range Y-Z AND quadkey is one of 436 values"

**Solution:** Restructure the query to make the optimizer use the PK correctly.

## Real-World Analogy

### Original Query (Slow)
Like searching a phone book by:
1. Finding everyone whose phone number starts with 555
2. Then checking if their last name is one of 436 specific names

### Optimized Query (Fast)
Like searching a phone book by:
1. Looking up each of the 436 specific last names (phone books are sorted by last name!)
2. For each person found, checking if their phone number starts with 555

**Which is faster?** Obviously the second approach, because the phone book is sorted by last name!

Same principle applies to your composite index `(quadkey, edge_id)`.
