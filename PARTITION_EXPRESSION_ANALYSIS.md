# Partition Expression Analysis: Can We Use Original main_quadkey in PK?

## Your Questions

### Question 1: Can we use original main_quadkey in PK but expression in PARTITION BY?
**Short Answer: Technically yes, but with significant constraints.**

### Question 2: Will partition pruning work with level 15 in WHERE clause but level 12 in partition function?
**Short Answer: It depends - may work but not guaranteed. Need to test.**

---

## Technical Analysis

### Option A: Expression in PARTITION BY (What you're asking about)

```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,  -- stores level 15
    map_id INTEGER NOT NULL,
    -- ... other columns ...
    
    -- PK MUST include the EXACT expression used in partitioning
    PRIMARY KEY (id, (FLOOR(main_quadkey / 1000)), map_id)
    
) PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id);
```

#### Key Constraints:
1. ✅ **You CAN use an expression in PARTITION BY**
2. ⚠️ **The PK MUST include that SAME expression** - e.g., `(FLOOR(main_quadkey / 1000))`
3. ⚠️ **The expression in PK must use parentheses** to indicate it's an expression
4. ❌ **This means the PK is NOT just `(id, main_quadkey, map_id)` but includes the computed expression**

#### Implications:
- Foreign key constraints must reference: `(id, expression, map_id)`
- This is **awkward** - FK tables would need to store or compute the expression too
- Not commonly done in practice

---

### Option B: Stored Computed Column (RECOMMENDED)

```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,      -- stores level 15
    main_quadkey_l12 INTEGER NOT NULL,  -- stores level 12 (explicitly set during INSERT)
    map_id INTEGER NOT NULL,
    -- ... other columns ...
    
    PRIMARY KEY (id, main_quadkey_l12, map_id)
    
) PARTITION BY HASH (main_quadkey_l12, map_id);

-- During data migration:
INSERT INTO signs_new (id, main_quadkey, main_quadkey_l12, map_id, ...)
SELECT 
    id,
    COALESCE(main_quadkey, 0),
    COALESCE(FLOOR(main_quadkey / 1000), 0) as main_quadkey_l12,
    map_id,
    ...
FROM signs
WHERE map_id IS NOT NULL;
```

#### Advantages:
- ✅ Clean PK structure: `(id, main_quadkey_l12, map_id)`
- ✅ FK constraints are straightforward
- ✅ **Guaranteed partition pruning** when you filter by `main_quadkey_l12`
- ✅ Can still query by level 15 `main_quadkey` if needed
- ✅ Can create function/trigger to auto-compute level 12 from level 15

---

### Option C: Generated Column (PostgreSQL 12+)

```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,      -- stores level 15
    main_quadkey_l12 INTEGER NOT NULL 
        GENERATED ALWAYS AS (FLOOR(main_quadkey / 1000)) STORED,
    map_id INTEGER NOT NULL,
    -- ... other columns ...
    
    PRIMARY KEY (id, main_quadkey_l12, map_id)
    
) PARTITION BY HASH (main_quadkey_l12, map_id);
```

#### Advantages:
- ✅ Automatically maintained
- ✅ No duplication in INSERT statements
- ✅ Clean PK structure
- ⚠️ **Requires PostgreSQL 12+**
- ⚠️ Small performance overhead on writes

---

## Partition Pruning Analysis

### Scenario 1: Using Expression in PARTITION BY

```sql
-- Table partitioned by: HASH(FLOOR(main_quadkey / 1000), map_id)

-- Query A: Filter by level 12 expression directly
SELECT * FROM signs_new 
WHERE FLOOR(main_quadkey / 1000) = 1656756 
  AND map_id = 42;
-- ✅ WILL prune partitions (exact match to partition key)

-- Query B: Filter by level 15 value
SELECT * FROM signs_new 
WHERE main_quadkey = 1656756156 
  AND map_id = 42;
-- ❓ MAY NOT prune partitions reliably
-- Planner needs to derive: 1656756156 → FLOOR(1656756156/1000) = 1656756
-- This is not guaranteed to work in all PostgreSQL versions
```

### Scenario 2: Using Stored Column (main_quadkey_l12)

```sql
-- Table partitioned by: HASH(main_quadkey_l12, map_id)

-- Query A: Filter by level 12 column
SELECT * FROM signs_new 
WHERE main_quadkey_l12 = 1656756 
  AND map_id = 42;
-- ✅ WILL prune partitions (exact match to partition key)

-- Query B: Filter by level 15 value
SELECT * FROM signs_new 
WHERE main_quadkey = 1656756156 
  AND map_id = 42;
-- ❌ WILL NOT prune partitions
-- No direct relationship between main_quadkey and partition key

-- Query C: Filter by both (if you know the relationship)
SELECT * FROM signs_new 
WHERE main_quadkey = 1656756156 
  AND main_quadkey_l12 = 1656756  -- computed by application
  AND map_id = 42;
-- ✅ WILL prune partitions
```

---

## Quadkey Format Analysis

Based on your samples:
```
1656756156  (10 digits)
1656755952  (10 digits)
```

### 🤔 Questions about these values:

**If these are level 15 quadkeys as integers:**
- Base-4 quadkeys have 15 digits (0-3 each)
- Maximum value: 3333333333333333 (15 threes in base-4)
- In decimal: 4^15 - 1 = 1,073,741,823
- Your values: ~1.6 billion

**Your values exceed the theoretical max for base-4 level 15 quadkeys!**

### Possible Explanations:

#### 1. These are NOT base-4 quadkey strings converted to integers
They might be:
- Morton codes (binary interleaved coordinates)
- Tile indices in a different system
- Hash values derived from coordinates

#### 2. These are partial tile IDs or coordinates
Perhaps they represent:
- X or Y coordinate at level 15
- Combined with another value to form full quadkey

#### 3. Different encoding scheme
Your organization uses a custom quadkey encoding.

### 🔍 To Determine Conversion Formula:

**Please run this query:**
```sql
SELECT 
    main_quadkey,
    map_id,
    ST_X(geometry_lla::geometry) as longitude,
    ST_Y(geometry_lla::geometry) as latitude,
    -- If you have a function to convert back to quadkey string:
    -- quadkey_to_string(main_quadkey, 15) as quadkey_string
FROM signs 
WHERE main_quadkey IS NOT NULL 
  AND geometry_lla IS NOT NULL
LIMIT 5;
```

**Or provide:**
1. Documentation on how `main_quadkey` is computed/encoded
2. Example showing relationship between coordinates and `main_quadkey` value
3. Existing functions in your codebase for quadkey conversion

---

## Conversion Formula Options

### If main_quadkey is string-based (seems unlikely given values):
```sql
-- Level 15 → Level 12: remove last 3 digits
main_quadkey_l12 = FLOOR(main_quadkey / 1000)

-- Example:
1656756156 / 1000 = 1656756.156
FLOOR(1656756156 / 1000) = 1656756
```

### If main_quadkey is Morton code (bitwise):
```sql
-- Level 15 → Level 12: right shift 6 bits (3 levels × 2 bits)
main_quadkey_l12 = main_quadkey >> 6

-- Example:
1656756156 >> 6 = 25886815
```

### If main_quadkey is tile X coordinate:
```sql
-- Level 15 → Level 12: divide by 2^3
main_quadkey_l12 = FLOOR(main_quadkey / 8)

-- Example:
1656756156 / 8 = 207094519.5
FLOOR(1656756156 / 8) = 207094519
```

**Which formula is correct?** We need to verify based on your spatial data.

---

## Recommendations

### Recommendation 1: Use Stored Column (Option B)
**Best for partition pruning reliability:**

```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,      -- original level 15
    main_quadkey_l12 INTEGER NOT NULL,  -- computed level 12
    map_id INTEGER NOT NULL,
    -- ... other columns ...
    PRIMARY KEY (id, main_quadkey_l12, map_id)
) PARTITION BY HASH (main_quadkey_l12, map_id);
```

- Clean PK for foreign keys
- Guaranteed partition pruning on `main_quadkey_l12`
- Application can query by either level 15 or level 12

### Recommendation 2: Create Conversion Function

```sql
-- Create helper function
CREATE OR REPLACE FUNCTION quadkey_to_level12(quadkey_l15 INTEGER)
RETURNS INTEGER AS $$
BEGIN
    -- Replace with correct formula once confirmed
    RETURN FLOOR(quadkey_l15 / 1000);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Use in queries for partition pruning
SELECT * FROM signs_new 
WHERE main_quadkey_l12 = quadkey_to_level12(1656756156)
  AND map_id = 42;
```

### Recommendation 3: Add Application-Level Helper

If most queries will filter by level 15 `main_quadkey`:
- Application should compute level 12 value
- Include both in WHERE clause for partition pruning

```python
# Python example
def get_signs_by_quadkey_l15(quadkey_l15, map_id):
    quadkey_l12 = quadkey_l15 // 1000  # adjust formula as needed
    
    query = """
        SELECT * FROM signs_new 
        WHERE main_quadkey = %s 
          AND main_quadkey_l12 = %s  -- enables partition pruning!
          AND map_id = %s
    """
    return execute_query(query, (quadkey_l15, quadkey_l12, map_id))
```

---

## Summary: Answering Your Questions

### Q1: Can we use original main_quadkey in PK with expression in PARTITION BY?

**Answer:** 
- ✅ Yes, technically possible
- ⚠️ But PK must include the expression: `PRIMARY KEY (id, (FLOOR(main_quadkey/1000)), map_id)`
- ❌ Makes foreign keys awkward
- **Not recommended** - use stored column instead

### Q2: Will partition pruning work with level 15 in WHERE but level 12 in partition?

**Answer:**
- ❓ **Unreliable** - depends on PostgreSQL version and query planner intelligence
- ✅ **Guaranteed pruning** only when WHERE clause matches partition key exactly
- 💡 **Solution**: Store both levels, include level 12 in WHERE clause

---

## Next Steps Required

**Before proceeding, please provide:**

1. ✅ **Confirm conversion formula**: How to convert level 15 → level 12?
   - Test: `SELECT FLOOR(1656756156 / 1000)` = 1656756 ← Is this correct?
   - Or different formula?

2. ✅ **Choose approach:**
   - **Option A**: Expression in PARTITION BY (not recommended)
   - **Option B**: Stored column `main_quadkey_l12` (recommended) ✅
   - **Option C**: Generated column (if PostgreSQL 12+)

3. ✅ **Confirm PK structure:**
   - `PRIMARY KEY (id, main_quadkey_l12, map_id)` ← Recommended
   - Or keep expression-based PK?

4. ✅ **Query pattern confirmation:**
   - Will application queries include level 12 value for pruning?
   - Or rely on planner to derive it?

**Once confirmed, I'll generate the complete migration scripts.**
