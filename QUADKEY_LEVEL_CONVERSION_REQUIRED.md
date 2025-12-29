# 🔴 CRITICAL: Quadkey Level Conversion Strategy Required

## Overview
Before proceeding with the partitioning migration, we need to define how to convert level 15 quadkeys to level 12 quadkeys.

---

## Background: Quadkey Levels

**Quadkeys** (Quadtree keys) are hierarchical spatial indexing systems:
- Each level subdivides space into 4 quadrants (2x2 grid)
- Level 0 = entire world (1 tile)
- Level 15 = 2^30 tiles (1,073,741,824 tiles)
- Level 12 = 2^24 tiles (16,777,216 tiles)

**Your Situation:**
- Current data stores **level 15 quadkeys** (fine granularity)
- Partitioning should use **level 12 quadkeys** (coarser granularity)
- Need to convert: Level 15 → Level 12 (truncate 3 levels)

---

## Quadkey Encoding Methods

### Method 1: String-based (Microsoft Bing Maps style)
Quadkeys as base-4 digit strings:
- Level 15: `"021301203012301"` (15 characters, each 0-3)
- Level 12: `"021301203012"` (12 characters, truncate last 3)

**Conversion**: `SUBSTRING(quadkey_string, 1, 12)`

### Method 2: Integer-based (String as Integer)
String digits stored as integer:
- Level 15: `21301203012301` (stored as INTEGER)
- Level 12: `21301203012` (remove last 3 digits)

**Conversion**: `FLOOR(main_quadkey / 1000)` or `FLOOR(main_quadkey / POWER(10, 3))`

### Method 3: Morton Code / Z-Order Curve (Bitwise)
Interleaved coordinate bits:
- Level 15: Uses 30 bits (2 bits per level × 15 levels)
- Level 12: Uses 24 bits (2 bits per level × 12 levels)

**Conversion**: `main_quadkey >> 6` (right shift 6 bits = 3 levels × 2 bits/level)

### Method 4: Custom Encoding
Your organization may have a custom encoding scheme.

---

## ❓ INFORMATION NEEDED

Please provide the following:

### 1. Sample Data
```sql
-- Run this query and share results:
SELECT 
    main_quadkey,
    map_id,
    ST_X(geometry_lla::geometry) as lon,
    ST_Y(geometry_lla::geometry) as lat
FROM signs 
WHERE main_quadkey IS NOT NULL 
LIMIT 10;
```

### 2. Quadkey Encoding Confirmation
Which encoding method do you use?
- [ ] Method 1: String-based (e.g., "021301203012301")
- [ ] Method 2: Integer from string digits (e.g., 21301203012301)
- [ ] Method 3: Morton code bitwise (e.g., binary interleaved coords)
- [ ] Method 4: Custom (please describe)

### 3. Conversion Formula
Based on your encoding, what is the exact conversion formula?

**Examples:**
```sql
-- For string-based stored as integer:
main_quadkey_l12 = FLOOR(main_quadkey / 1000)

-- For Morton code:
main_quadkey_l12 = main_quadkey >> 6

-- For string manipulation:
main_quadkey_l12 = CAST(LEFT(CAST(main_quadkey AS TEXT), 12) AS INTEGER)
```

**Your formula:** `_____________________________________`

### 4. Column Strategy Decision

Choose one approach:

#### Option A: Replace Existing Column ❌ NOT RECOMMENDED
- Change `main_quadkey` from level 15 to level 12
- Lose level 15 precision
- **Pros**: Simple schema
- **Cons**: Data loss, can't revert

#### Option B: Add Separate Column ✅ RECOMMENDED
- Keep `main_quadkey` (level 15) unchanged
- Add new column `main_quadkey_l12` (level 12) for partitioning
- **Pros**: Preserve original data, can use either level
- **Cons**: Small storage overhead (~4 bytes per row)

#### Option C: Computed/Generated Column
- Keep `main_quadkey` (level 15)
- Add GENERATED ALWAYS column: `main_quadkey_l12 AS (conversion_formula)`
- **Pros**: No duplication, auto-maintained
- **Cons**: Can't partition on generated columns in all PG versions, performance impact

**I recommend Option B** - add `main_quadkey_l12` column.

### 5. Partitioning Key Specification

Based on your choice:

**If Option A (replace):**
```sql
PARTITION BY HASH (main_quadkey, map_id)  -- now level 12
```

**If Option B (separate column):**
```sql
PARTITION BY HASH (main_quadkey_l12, map_id)  -- partition on L12
```

**If Option C (computed):**
```sql
-- May not work in all PostgreSQL versions
PARTITION BY HASH (main_quadkey_l12, map_id)
```

### 6. Foreign Key Implications

If referencing tables need `main_quadkey` column (to match composite PK):

**Should they store:**
- Level 12 (matches partition key) - recommended for FK performance
- Level 15 (matches source precision) - if needed for analysis
- Both levels (if both needed)

---

## Example Scenario (Please Confirm or Correct)

**Assumption:** You use Method 2 (integer from string digits)

```sql
-- Source data in signs table
main_quadkey = 123456789012345  (level 15, 15 digits)
map_id = 42

-- Conversion to level 12
main_quadkey_l12 = FLOOR(123456789012345 / 1000) = 123456789012

-- Partitioned table schema
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,        -- original level 15
    main_quadkey_l12 INTEGER NOT NULL,    -- computed level 12
    map_id INTEGER NOT NULL,
    -- ... other columns ...
    PRIMARY KEY (id, main_quadkey_l12, map_id)
) PARTITION BY HASH (main_quadkey_l12, map_id);

-- Data migration
INSERT INTO signs_new (id, main_quadkey, main_quadkey_l12, map_id, ...)
SELECT 
    id,
    COALESCE(main_quadkey, 0) as main_quadkey,
    COALESCE(FLOOR(main_quadkey / 1000), 0) as main_quadkey_l12,
    map_id,
    -- ... other columns ...
FROM signs
WHERE map_id IS NOT NULL;
```

**Is this correct?** Please confirm or provide corrections.

---

## Decision Summary Template

Please fill in:

```
1. Encoding Method: [ Method 1 / Method 2 / Method 3 / Method 4: ___ ]

2. Conversion Formula: 
   main_quadkey_l12 = _________________________________

3. Column Strategy: [ Option A / Option B / Option C ]

4. New Column Name (if Option B): main_quadkey_l12 OR ___________

5. FK Storage Level: [ Level 12 / Level 15 / Both ]

6. Sample Validation:
   - Example main_quadkey (L15): _____________
   - Converted to (L12): _____________
   
7. Partition Key Confirmation:
   PARTITION BY HASH (__________, map_id)
```

---

## Next Steps

Once you provide the above information, I will:

1. ✅ Update the migration script with correct quadkey conversion
2. ✅ Define the exact table schema (with or without L12 column)
3. ✅ Update FK constraints with correct columns
4. ✅ Create validation queries to verify conversion accuracy
5. ✅ Generate complete migration scripts

---

## Additional Files Created

- ✅ `SIGNS_PARTITIONING_ASSUMPTIONS.md` - All confirmed assumptions
- ✅ `analyze_referencing_tables.sql` - Script to check existing columns in FK tables

**Run the analyze script** to see which referencing tables already have `main_quadkey` and `map_id` columns.

