# Analysis: PK on Column vs Expression in PARTITION BY

## Your Proposed Structure

```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,
    map_id INTEGER NOT NULL,
    -- ... other columns ...
    
    PRIMARY KEY (id, main_quadkey, map_id)  -- ← Column
) PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id);  -- ← Expression
```

---

## Key Question: Is This Valid in PostgreSQL?

### PostgreSQL's Partitioning Rule

From PostgreSQL documentation:
> "A PRIMARY KEY constraint (and generally any UNIQUE constraint) on a partitioned table **must include all the partition key columns**."

### But What if Partition Key is an Expression?

Your case:
- **Partition key**: `FLOOR(main_quadkey / 1000), map_id`
- **Primary key**: `id, main_quadkey, map_id`

The PK includes `main_quadkey` (the column), but the partition uses `FLOOR(main_quadkey / 1000)` (an expression).

---

## Theoretical Analysis

### Why This MIGHT Work ✅

**Logic**: Having `main_quadkey` in the PK is **more specific** than having `FLOOR(main_quadkey / 1000)`.

- If two rows have different `main_quadkey` values, they MUST be different rows
- Even if two rows have the same `FLOOR(main_quadkey / 1000)`, they can have different `main_quadkey`
- Therefore, uniqueness on `main_quadkey` **implies** distinction on `FLOOR(main_quadkey / 1000)`

**Example**:
```
Row 1: id=1, main_quadkey=1656756156, map_id=42
       FLOOR(1656756156/1000) = 1656756

Row 2: id=2, main_quadkey=1656756999, map_id=42
       FLOOR(1656756999/1000) = 1656756  (SAME!)

Both rows go to the same partition (same FLOOR value).
But PK uniqueness is maintained because main_quadkey differs.
```

### Why This MIGHT NOT Work ❌

**Concern**: PostgreSQL may strictly require the **exact partition key expressions** in the PK.

- The partition key is `(FLOOR(main_quadkey / 1000), map_id)`
- The PK must include these exact expressions: `PRIMARY KEY (id, (FLOOR(main_quadkey / 1000)), map_id)`
- PostgreSQL may not accept a "more specific" column as a substitute

---

## Testing Required

I've created `test_pk_column_vs_partition_expression.sql` to test this.

Run it to determine:
1. **Does PostgreSQL accept this structure?**
2. **If yes, how does partition pruning behave?**

---

## Expected Test Results

### Scenario A: PostgreSQL ACCEPTS This Structure ✅

If the test succeeds, you can use:
```sql
PRIMARY KEY (id, main_quadkey, map_id)
PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)
```

**Implications:**

1. **Foreign Keys**: Clean structure!
   ```sql
   FOREIGN KEY (sign_id, main_quadkey, map_id) 
   REFERENCES signs(id, main_quadkey, map_id)
   ```
   Referencing tables store the full `main_quadkey` (level 15), not level 12.

2. **Partition Pruning**: **STILL UNRELIABLE** when querying by column alone
   ```sql
   -- Query A: By expression - WILL PRUNE ✅
   WHERE FLOOR(main_quadkey / 1000) = 1656756 AND map_id = 42
   
   -- Query B: By column - MAY NOT PRUNE ❌
   WHERE main_quadkey = 1656756156 AND map_id = 42
   ```

3. **Storage**: No duplication (only one quadkey column)

4. **Application Impact**: Queries must use expression for guaranteed pruning
   ```sql
   -- Python example
   quadkey_l12 = quadkey // 1000
   query = """
       SELECT * FROM signs 
       WHERE FLOOR(main_quadkey / 1000) = %s 
         AND map_id = %s
   """
   execute(query, (quadkey_l12, map_id))
   ```

### Scenario B: PostgreSQL REJECTS This Structure ❌

If the test fails with error like:
```
ERROR: unique constraint on partitioned table must include all partitioning columns
```

Then you MUST use:
```sql
PRIMARY KEY (id, (FLOOR(main_quadkey / 1000)), map_id)
PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)
```

OR use the stored column approach:
```sql
main_quadkey_l12 INTEGER NOT NULL,
PRIMARY KEY (id, main_quadkey_l12, map_id)
PARTITION BY HASH (main_quadkey_l12, map_id)
```

---

## Comparison: Your Approach vs Stored Column

### Option 1: Your Proposed Approach (if it works)

```sql
PRIMARY KEY (id, main_quadkey, map_id)
PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)
```

**Pros:**
- ✅ No column duplication
- ✅ Foreign keys reference full-precision `main_quadkey`
- ✅ Simple schema

**Cons:**
- ❓ May not be accepted by PostgreSQL (needs testing)
- ❌ Partition pruning unreliable with column-based queries
- ❌ Application must use expression in queries

### Option 2: Stored Column Approach

```sql
main_quadkey INTEGER NOT NULL,      -- level 15
main_quadkey_l12 INTEGER NOT NULL,  -- level 12
PRIMARY KEY (id, main_quadkey_l12, map_id)
PARTITION BY HASH (main_quadkey_l12, map_id)
```

**Pros:**
- ✅ Guaranteed to work in PostgreSQL
- ✅ Reliable partition pruning on `main_quadkey_l12`
- ✅ Can query by either level
- ✅ Clear, explicit schema

**Cons:**
- ⚠️ Storage overhead (~4 bytes per row)
- ⚠️ Foreign keys need `main_quadkey_l12` column (or full precision `main_quadkey`)
- ⚠️ Must maintain both columns

---

## Partition Pruning Deep Dive

Assuming your approach works, here's how queries behave:

### Query Pattern 1: Using Expression (Matches Partition Key)
```sql
SELECT * FROM signs 
WHERE FLOOR(main_quadkey / 1000) = 1656756 
  AND map_id = 42;
```
- ✅ **WILL prune partitions** (exact match to partition key)
- PostgreSQL can determine which partition(s) to scan

### Query Pattern 2: Using Column Value
```sql
SELECT * FROM signs 
WHERE main_quadkey = 1656756156 
  AND map_id = 42;
```
- ❓ **MAY NOT prune reliably**
- Depends on PostgreSQL version and planner intelligence
- Planner would need to:
  1. Recognize: `main_quadkey = 1656756156`
  2. Derive: `FLOOR(1656756156 / 1000) = 1656756`
  3. Use derived value for partition selection
- This is NOT guaranteed

### Query Pattern 3: Range on Column
```sql
SELECT * FROM signs 
WHERE main_quadkey BETWEEN 1656756000 AND 1656756999
  AND map_id = 42;
```
- ❌ **WILL NOT prune**
- Range on column can't be easily translated to partition key expression
- All partitions scanned

### Query Pattern 4: Expression + Column (Best Practice)
```sql
SELECT * FROM signs 
WHERE main_quadkey = 1656756156 
  AND FLOOR(main_quadkey / 1000) = 1656756  -- redundant but ensures pruning
  AND map_id = 42;
```
- ✅ **WILL prune partitions**
- Application computes and provides both values
- Redundant but guarantees performance

---

## Recommendations

### If Your Approach Works (Test Confirms)

**Use it if:**
- ✅ You want simpler schema (no duplicate columns)
- ✅ You can modify application to use expressions in queries
- ✅ Most queries can include `FLOOR(main_quadkey / 1000)` in WHERE clause

**Migration strategy:**
```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,
    map_id INTEGER NOT NULL,
    -- ... all other columns ...
    PRIMARY KEY (id, main_quadkey, map_id)
) PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id);

-- Create helper function
CREATE FUNCTION quadkey_to_l12(qk INTEGER) RETURNS INTEGER AS $$
    SELECT FLOOR(qk / 1000);
$$ LANGUAGE SQL IMMUTABLE;

-- Application uses:
WHERE FLOOR(main_quadkey / 1000) = quadkey_to_l12(user_input)
  AND map_id = :map_id
```

### If You Want Guaranteed Partition Pruning

**Use stored column if:**
- ✅ You want reliable, predictable partition pruning
- ✅ You want application to query by column value without expression
- ✅ You're okay with small storage overhead

**Migration strategy:**
```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,
    main_quadkey_l12 INTEGER NOT NULL,
    map_id INTEGER NOT NULL,
    -- ... all other columns ...
    PRIMARY KEY (id, main_quadkey_l12, map_id)
) PARTITION BY HASH (main_quadkey_l12, map_id);

-- Application can provide both:
WHERE main_quadkey = :quadkey
  AND main_quadkey_l12 = :quadkey_l12  -- computed by app
  AND map_id = :map_id
```

---

## Foreign Key Implications

### With Your Approach
Referencing tables:
```sql
ALTER TABLE sign_to_edge_association
ADD COLUMN main_quadkey INTEGER,
ADD COLUMN map_id INTEGER;

-- FK references full columns
FOREIGN KEY (sign_id, main_quadkey, map_id) 
REFERENCES signs(id, main_quadkey, map_id);
```
- Stores full precision `main_quadkey` (level 15)
- No level 12 conversion needed in referencing tables

### With Stored Column Approach
Referencing tables need to decide:
```sql
-- Option A: Store level 12 (matches PK)
ADD COLUMN main_quadkey_l12 INTEGER,
ADD COLUMN map_id INTEGER;
FOREIGN KEY (sign_id, main_quadkey_l12, map_id) 
REFERENCES signs(id, main_quadkey_l12, map_id);

-- Option B: Store both levels (if needed)
ADD COLUMN main_quadkey INTEGER,
ADD COLUMN main_quadkey_l12 INTEGER,
ADD COLUMN map_id INTEGER;
```

---

## Next Steps

1. **Run the test script**:
   ```bash
   psql your_test_db < test_pk_column_vs_partition_expression.sql
   ```

2. **If test succeeds** (PostgreSQL accepts the structure):
   - Decide if partition pruning limitations are acceptable
   - Plan application changes to use expressions in queries
   - I'll generate migration scripts using your approach

3. **If test fails** (PostgreSQL rejects it):
   - Choose between:
     - Expression in PK: `PRIMARY KEY (id, (FLOOR(...)), map_id)`
     - Stored column: `main_quadkey_l12`
   - I'll generate migration scripts for chosen approach

4. **Still need**: Quadkey conversion formula confirmation
   - Is `FLOOR(main_quadkey / 1000)` correct for level 15 → 12?
   - Or different formula needed?

---

## Summary

**Your proposed structure:**
```sql
PRIMARY KEY (id, main_quadkey, map_id)
PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)
```

- ❓ **May or may not work** - test required
- ⚠️ **Partition pruning unreliable** without expression in queries
- ✅ **Simpler schema** if it works
- 🔧 **Application changes needed** for optimal performance

**Test first, then proceed with migration scripts based on results!**
