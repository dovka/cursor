# 🎯 Summary: Next Steps for Signs Table Partitioning

## Current Status: ⏸️ AWAITING QUADKEY CONVERSION SPECIFICATION

---

## ✅ What's Been Confirmed

1. **Partitioning Strategy**: HASH partitioning with 20 buckets
2. **Partition Keys**: `(main_quadkey_or_derived, map_id)`
3. **Primary Key**: `(id, partition_key_columns, map_id)` - Option A ordering
4. **NULL Handling**: Only migrate `map_id IS NOT NULL`, set `main_quadkey = 0` if NULL
5. **FK Column Naming**: Use `main_quadkey`, `map_id` (no prefixes)
6. **Indexes**: Keep all 11 existing indexes
7. **Environment**: POC on test instance

---

## ❓ Critical Decisions Needed

### 1. Quadkey Encoding Method 🔴 MOST CRITICAL

Your `main_quadkey` values (~1.65 billion) **exceed** the theoretical maximum for:
- Traditional base-4 quadkey strings (max: 1.07 billion)
- Level 15 Morton codes (max: 1.07 billion)

**Possible encodings:**
- Level 16+ tile index: `x * 2^16 + y`
- Custom Morton encoding
- Offset-based quadkey system
- Single coordinate (not full location)

**REQUIRED:** Please specify:
- How is `main_quadkey` computed from coordinates?
- What zoom/level is it actually at?
- Are there existing conversion functions in your codebase?

**See `QUADKEY_FORMAT_ANALYSIS.md` for detailed analysis**

---

### 2. Level 15 → Level 12 Conversion Formula 🔴 REQUIRED

Without knowing the encoding, we cannot write the conversion formula.

**Options being considered:**

#### Option A: Simple Division (if string-based)
```sql
main_quadkey_l12 = FLOOR(main_quadkey / 1000)
Example: 1656756156 → 1656756
```
⚠️ **Unlikely to be correct** based on value analysis

#### Option B: Tile Coordinate Conversion (if tile index at level 16)
```sql
x = FLOOR(main_quadkey / 65536)
y = main_quadkey % 65536
x_l12 = FLOOR(x / 16)
y_l12 = FLOOR(y / 16)
main_quadkey_l12 = x_l12 * 4096 + y_l12
```
⭐ **More likely** based on value range

#### Option C: Morton Code Conversion (if bitwise)
```sql
-- Requires bitwise deinterleaving and reinterleaving
-- Complex custom function needed
```

#### Option D: Custom Function
```sql
-- You provide the function
main_quadkey_l12 = your_conversion_function(main_quadkey)
```

**REQUIRED:** Specify which formula is correct

---

### 3. Column Strategy for Partition Key 🔴 REQUIRED

Based on your questions about partition pruning, you have these options:

#### Option A: Expression in PARTITION BY
```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,  -- stores level 15/16
    map_id INTEGER NOT NULL,
    PRIMARY KEY (id, (conversion_expression), map_id)
) PARTITION BY HASH (conversion_expression, map_id);
```

**Pros:**
- Only one column for quadkey
- No data duplication

**Cons:**
- ❌ PK includes expression - awkward for FKs
- ❌ Partition pruning unreliable when filtering by `main_quadkey`
- ❌ Application queries need to use expression for pruning

**Verdict:** ❌ NOT RECOMMENDED

---

#### Option B: Stored Column ⭐ RECOMMENDED
```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,      -- original level 15/16
    main_quadkey_l12 INTEGER NOT NULL,  -- computed level 12
    map_id INTEGER NOT NULL,
    PRIMARY KEY (id, main_quadkey_l12, map_id)
) PARTITION BY HASH (main_quadkey_l12, map_id);
```

**Pros:**
- ✅ Clean PK structure for FKs
- ✅ Guaranteed partition pruning on `main_quadkey_l12`
- ✅ Can query by either level
- ✅ Clear, explicit schema

**Cons:**
- Small storage overhead (~4 bytes per row)
- Need to maintain both columns on insert/update

**Verdict:** ✅ RECOMMENDED

---

#### Option C: Generated Column (PostgreSQL 12+)
```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,
    main_quadkey_l12 INTEGER NOT NULL 
        GENERATED ALWAYS AS (conversion_expression) STORED,
    map_id INTEGER NOT NULL,
    PRIMARY KEY (id, main_quadkey_l12, map_id)
) PARTITION BY HASH (main_quadkey_l12, map_id);
```

**Pros:**
- ✅ Automatically maintained
- ✅ Clean PK structure
- ✅ No duplication in INSERT statements

**Cons:**
- Requires PostgreSQL 12+
- Small write performance overhead
- Must verify conversion expression is immutable

**Verdict:** ✅ GOOD ALTERNATIVE if PG12+

---

### 4. Partition Pruning Strategy

Based on your questions, here's how pruning works:

| Query Pattern | Option A (Expression) | Option B (Stored) | Option C (Generated) |
|--------------|----------------------|-------------------|---------------------|
| `WHERE main_quadkey_l12 = X AND map_id = Y` | ✅ Prunes | ✅ Prunes | ✅ Prunes |
| `WHERE main_quadkey = X AND map_id = Y` | ❓ Maybe | ❌ No pruning | ❓ Maybe |
| `WHERE expression = X AND map_id = Y` | ✅ Prunes | N/A | N/A |
| `WHERE main_quadkey = X AND main_quadkey_l12 = Y AND map_id = Z` | N/A | ✅ Prunes | ✅ Prunes |

**Key Insight:** For reliable partition pruning, queries must filter by the **exact partition key columns**.

**Recommendation:** 
- Use Option B (stored column)
- Application should compute level 12 value
- Include `main_quadkey_l12` in WHERE clause:
  ```sql
  WHERE main_quadkey = 1656756156 
    AND main_quadkey_l12 = compute_l12(1656756156)  -- enables pruning!
    AND map_id = 42
  ```

---

## 📊 Recommended Approach Summary

### Schema Design
```sql
CREATE TABLE signs_new (
    -- Primary columns
    id BIGINT NOT NULL,
    
    -- Quadkey at two levels
    main_quadkey INTEGER NOT NULL,      -- original precision (level 15/16)
    main_quadkey_l12 INTEGER NOT NULL,  -- for partitioning (level 12)
    
    -- Other partition key
    map_id INTEGER NOT NULL,
    
    -- All other existing columns...
    time_created TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
    external_id BIGINT,
    location GEOMETRY(PointZ),
    -- ... etc ...
    
    -- Primary key includes partition keys
    PRIMARY KEY (id, main_quadkey_l12, map_id)
    
) PARTITION BY HASH (main_quadkey_l12, map_id);
```

### 20 Partitions
```sql
CREATE TABLE signs_p00 PARTITION OF signs_new FOR VALUES WITH (MODULUS 20, REMAINDER 0);
CREATE TABLE signs_p01 PARTITION OF signs_new FOR VALUES WITH (MODULUS 20, REMAINDER 1);
-- ... through ...
CREATE TABLE signs_p19 PARTITION OF signs_new FOR VALUES WITH (MODULUS 20, REMAINDER 19);
```

### Indexes (Created AFTER table and partitions)
```sql
-- Primary key index (automatic)
-- Then create all other indexes:
CREATE INDEX idx_signs_geometry_lla ON signs_new USING GIST (geometry_lla);
CREATE INDEX ix_signs_base_map_uuid ON signs_new (base_map_uuid);
-- ... etc for all 11 indexes
```

### Foreign Key Updates
All 10 referencing tables need:
- Add column: `main_quadkey_l12 INTEGER` (or `main_quadkey` if doesn't exist)
- Add column: `map_id INTEGER` (if doesn't exist)
- Backfill from signs table
- Update FK constraint to reference `signs(id, main_quadkey_l12, map_id)`

---

## 🔍 Information Still Needed

Before I can generate migration scripts, please provide:

### 1. Quadkey Encoding Confirmation
Run this query and share results:
```sql
SELECT 
    main_quadkey,
    ST_X(geometry_lla::geometry) as longitude,
    ST_Y(geometry_lla::geometry) as latitude
FROM signs 
WHERE main_quadkey IS NOT NULL 
  AND geometry_lla IS NOT NULL
ORDER BY main_quadkey
LIMIT 10;
```

### 2. Existing Conversion Functions
Check your codebase for:
- Functions that compute `main_quadkey` from lat/lon
- Functions that convert between zoom levels
- Any quadkey utility functions

Search for: `quadkey`, `tile_x`, `tile_y`, `morton`, etc.

### 3. Conversion Formula Decision
Based on encoding, which formula should be used?
- Simple division?
- Tile coordinate extraction?
- Bitwise operations?
- Custom function?

### 4. Column Strategy Confirmation
Choose one:
- ✅ Option B: Stored column `main_quadkey_l12` (recommended)
- Option C: Generated column (if PG12+)
- Option A: Expression in PARTITION BY (not recommended)

---

## 📁 Files Created for Your Review

1. **`SIGNS_PARTITIONING_ASSUMPTIONS.md`** - All confirmed assumptions ✅
2. **`QUADKEY_LEVEL_CONVERSION_REQUIRED.md`** - Detailed quadkey questions ❓
3. **`PARTITION_EXPRESSION_ANALYSIS.md`** - Expression vs stored column analysis 📊
4. **`QUADKEY_FORMAT_ANALYSIS.md`** - Analysis of your quadkey encoding 🔍
5. **`test_partition_pruning.sql`** - Test script to verify pruning behavior 🧪
6. **`analyze_referencing_tables.sql`** - Script to check FK table columns 📋
7. **`NEXT_STEPS_SUMMARY.md`** (this file) - Complete summary 🎯

---

## ⏭️ Once Information is Provided

I will immediately generate:

1. **`01_signs_partitioning_migration.sql`**
   - Create partitioned table with 20 partitions
   - All column definitions with correct quadkey conversion
   - Primary key creation
   - All 11 indexes
   
2. **`02_signs_data_migration.sql`**
   - Data migration with correct level 12 computation
   - NULL handling as specified
   - Validation queries

3. **`03_signs_fk_updates.sql`**
   - Updates for all 10 referencing tables
   - Add necessary columns
   - Backfill data
   - Update FK constraints

4. **`04_signs_cutover.sql`**
   - Table rename operations
   - Final validation
   - Rollback procedures

5. **`05_signs_validation.sql`**
   - Data integrity checks
   - Partition distribution analysis
   - Query performance tests

---

## 🚀 Ready to Proceed

Please provide the quadkey conversion specification, and I'll generate all migration scripts immediately!

**Key Questions to Answer:**
1. What is the encoding method for `main_quadkey`?
2. What is the exact formula to convert level 15/16 → level 12?
3. Which column strategy do you prefer (B or C)?

