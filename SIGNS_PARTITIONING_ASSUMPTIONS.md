# Signs Table Partitioning - Assumptions & Confirmation Required

## Overview
Repartition the `signs` table using HASH partitioning on `(main_quadkey, map_id)` with 20 buckets while maintaining referential integrity.

---

## CRITICAL ASSUMPTIONS - PLEASE CONFIRM

### 1. Partitioning Strategy
- **Partition Type**: HASH partitioning
- **Partition Keys**: `main_quadkey` and `map_id` (in that order)
- **Number of Partitions**: 20 buckets (MODULUS 20, REMAINDER 0-19)
- **Partition Naming**: `signs_p00`, `signs_p01`, ... `signs_p19`

**❓ CONFIRM**: Is HASH partitioning on `(main_quadkey, map_id)` correct, or do you prefer LIST or RANGE partitioning?

---

### 2. Primary Key Configuration
- **New Primary Key**: `(id, main_quadkey, map_id)`
- **PK Order Option A**: `PRIMARY KEY (id, main_quadkey, map_id)` - optimized for id lookups
- **PK Order Option B**: `PRIMARY KEY (main_quadkey, map_id, id)` - optimized for partition pruning

**❓ CONFIRM**: Which PK column order do you prefer? (Option A recommended for backward compatibility)

- **PK Constraint Name**: `signs_pkey` (keep existing name)
- **PK Created**: AFTER table and partitions are created, using separate ALTER TABLE statement

---

### 3. Data Constraints for Partitioning
**CRITICAL**: Both `main_quadkey` and `map_id` MUST be NOT NULL for partitioning to work.

**Current Schema**: 
- `main_quadkey INTEGER` (nullable)
- `map_id INTEGER` (nullable)

**❓ CONFIRM**: 
- Are there existing rows with NULL values in `main_quadkey` or `map_id`?
- If yes, what should we do with them?
  - Option A: Set a default value (e.g., -1 or 0) for NULL values
  - Option B: Exclude them from migration (keep in separate non-partitioned table)
  - Option C: Fail migration if NULLs exist

---

### 4. Foreign Key Relationships
The following 10 tables reference `signs(id)` and will need to be updated:

#### Tables That Reference Signs:
1. `alternating_lane_sign_association` → `sign_id` references `signs(id)`
2. `dp_stop_point_group_to_tfl_associations` → `tfl_id` references `signs(id)`
3. `dp_stop_point_ra_association` → `sign_id` references `signs(id)`
4. `dp_stop_point_sign_association` → `sign_id` references `signs(id)`
5. `dp_stop_point_tlf_association` → `sign_id` references `signs(id)`
6. `ltwa_dp_stop_point_to_tfl_association` → `tfl_id` references `signs(id)`
7. `sign_alternative_observation_associations` → `sign_id` references `signs(id)`
8. `sign_supplementary_type_associations` → `sign_id` references `signs(id)`
9. `sign_to_dp_association` → `sign_id` references `signs(id)`
10. `sign_to_edge_association` → `sign_id` references `signs(id)`

**Required Changes for Each Referencing Table**:
- Add columns: `sign_main_quadkey INTEGER`, `sign_map_id INTEGER` (or similar naming)
- Update foreign key to reference: `signs(id, main_quadkey, map_id)`
- Backfill these columns with data from signs table
- Add indexes on the new FK columns

**❓ CONFIRM**:
- Do all these referencing tables need to be updated? (Required: YES for partitioning to work)
- Preferred naming convention for new columns:
  - Option A: `sign_main_quadkey`, `sign_map_id` 
  - Option B: `main_quadkey`, `map_id` (if not already used)
  - Option C: Custom naming you specify

---

### 5. Index Recreation Strategy
All indexes will be created AFTER the partitioned table structure is complete.

**Indexes to Recreate** (based on provided schema):
1. `idx_signs_geometry_lla` - GIST index on `geometry_lla`
2. `ix_signs_base_map_uuid` - BTREE on `base_map_uuid`
3. `ix_signs_cell_uuid` - BTREE on `cell_uuid`
4. `ix_signs_edge_id` - BTREE on `edge_id`
5. `ix_signs_edge_s` - BTREE on `edge_s`
6. `ix_signs_external_id` - BTREE on `external_id`
7. `ix_signs_main_quadkey` - BTREE on `main_quadkey`
8. `ix_signs_map_id` - BTREE on `map_id`
9. `ix_signs_topo_db_id` - BTREE on `topo_db_id`
10. `ix_signs_uuid` - BTREE on `uuid`
11. `signs_base_map_uuid_geometry_lla_idx` - GIST on `(base_map_uuid, geometry_lla)`

**❓ CONFIRM**: Are all these indexes still needed? Any to add or remove?

---

### 6. Migration Approach
**Recommended Strategy** (Zero Downtime):

```
Phase 1: Preparation
- Create new partitioned table `signs_new` with all partitions
- Add PK and indexes to `signs_new`
- Add new FK columns to all referencing tables

Phase 2: Data Migration
- Copy all data from `signs` to `signs_new`
- Backfill FK columns in referencing tables
- Validate data integrity

Phase 3: Cutover
- Begin transaction
- Drop old FK constraints on referencing tables
- Create new FK constraints pointing to signs_new(id, main_quadkey, map_id)
- Rename signs → signs_old
- Rename signs_new → signs
- Commit transaction

Phase 4: Cleanup
- Drop signs_old after validation period
```

**❓ CONFIRM**: 
- Is zero-downtime migration required?
- Can we accept a brief maintenance window for the cutover?
- What is your preferred validation period before dropping old table?

---

### 7. Sequence and Default Values
- **Current**: `id` uses `nextval('signs_id_seq'::regclass)`
- **Migration**: Keep the same sequence, no changes needed
- **Current**: `time_created` defaults to `now()`
- **Migration**: Preserve all default values

**❓ CONFIRM**: Keep all existing sequences and defaults? (Recommended: YES)

---

### 8. Foreign Key Constraints from Signs
Signs table has 3 outbound foreign keys:
1. `signs_edge_id_fkey` → `edges(id)`
2. `signs_system_type_id_fkey` → `system_types(id)`
3. `signs_traffic_sign_type_id_fkey` → `traffic_sign_types(id)`

**Migration**: These will be preserved as-is in the partitioned table.

**❓ CONFIRM**: Keep these FK constraints? (Recommended: YES)

---

### 9. Performance Considerations
With 20 hash partitions:
- Each partition will contain ~5% of data
- Queries filtering by `main_quadkey` and/or `map_id` will benefit from partition pruning
- Queries not filtering by partition keys will scan all 20 partitions
- PK lookups by `id` alone will scan all partitions (unless you also provide quadkey/map_id)

**❓ CONFIRM**: 
- Is this acceptable for your query patterns?
- Do most queries filter by `main_quadkey` or `map_id`?

---

### 10. Rollback Plan
A rollback script will be provided to:
- Rename tables back to original names
- Restore original FK constraints
- Drop the partitioned structure if needed

**❓ CONFIRM**: Required rollback provisions?

---

## ✅ CONFIRMED DECISIONS

1. ✅ HASH partitioning on `(main_quadkey, map_id)` with 20 buckets
2. ✅ **PK column order**: `PRIMARY KEY (id, main_quadkey, map_id)` - Option A selected
   - Note: Can create separate index `(main_quadkey, map_id, id)` for partition pruning optimization
3. ✅ **NULL handling**: 
   - Only migrate rows where `map_id IS NOT NULL`
   - Set `main_quadkey = 0` if NULL at source
4. ✅ **FK column naming**: Use `main_quadkey`, `map_id` (Option B)
   - Action required: Identify which referencing tables already have these columns
   - Make NO changes until confirmed
5. ✅ Keep all 11 indexes
6. ✅ **Migration type**: POC on test instance, defer detailed migration requirements for now
7. ✅ Keep existing sequences and defaults
8. ✅ Preserve outbound FK constraints from signs table
9. ✅ Acceptable that queries without partition key filters scan all partitions
10. ⏸️ Rollback requirements deferred (POC environment)

---

---

## 🔴 CRITICAL: QUADKEY LEVEL CONVERSION (PENDING DEFINITION)

### Current Situation
- **Source data**: Contains level 15 quadkeys (stored in `main_quadkey` column)
- **Partitioning requirement**: Use level 12 quadkeys for partitioning
- **Conversion needed**: Level 15 → Level 12 (truncate 3 levels)

### Questions Requiring Clarification

#### 1. Quadkey Storage Format
The `main_quadkey` column is defined as `INTEGER`. 

**❓ How is the quadkey encoded in the integer?**
- Option A: Quadkey string converted to integer (e.g., "023010213" → 23010213)
- Option B: Morton code / Z-order curve integer representation
- Option C: Custom encoding scheme

**Example**: If level 15 quadkey is "023010213012301" (15 digits), how do we convert to level 12?
- String truncation: "023010213012301" → "023010213012" (first 12 characters)
- Integer division: Depends on encoding scheme

#### 2. Column Strategy
**❓ Which approach do you prefer?**

**Option A: Single Column (Level 12 Only)**
- Store only level 12 quadkey in `main_quadkey` column
- Convert during migration: `main_quadkey_level12 = convert_to_level12(main_quadkey_level15)`
- Partition on the converted level 12 value
- **Pros**: Simple, clean schema
- **Cons**: Lose level 15 precision, may need to recompute if needed

**Option B: Dual Columns**
- Keep existing `main_quadkey` (level 15) as-is
- Add new column `main_quadkey_l12` or `partition_quadkey` (level 12)
- Partition on the level 12 column
- **Pros**: Preserve original data, can query either level
- **Cons**: Data duplication, more storage

**Option C: Computed Column**
- Keep `main_quadkey` (level 15)
- Add GENERATED column that computes level 12 on-the-fly
- Partition on the generated column
- **Pros**: No duplication, always in sync
- **Cons**: May impact performance, PostgreSQL limitations

#### 3. Conversion Function
**❓ Please specify the exact conversion logic:**

```sql
-- Example conversions (need your confirmation):

-- If quadkey is stored as string-like integer:
-- Level 15: 23010213012301 (14 digits actual, conceptually 15 levels including root)
-- Level 12: 23010213012 (11 digits, remove last 3)

-- Option 1: Simple integer division
main_quadkey_l12 = main_quadkey / 1000  -- if base-10 per level

-- Option 2: String manipulation
main_quadkey_l12 = CAST(LEFT(CAST(main_quadkey AS TEXT), 12) AS INTEGER)

-- Option 3: Bitwise operation (if Morton encoding)
main_quadkey_l12 = main_quadkey >> (2 * 3)  -- shift right 6 bits (2 bits per level * 3 levels)

-- Option 4: Custom function
main_quadkey_l12 = your_quadkey_truncate_function(main_quadkey, 15, 12)
```

#### 4. Partition Key Decision
**❓ Partition key will be:**
- `PARTITION BY HASH (main_quadkey_l12, map_id)` - if using separate column
- `PARTITION BY HASH (truncate_quadkey(main_quadkey), map_id)` - if using function
- `PARTITION BY HASH (main_quadkey / 1000, map_id)` - if using expression

#### 5. Foreign Key Impact
If we change `main_quadkey` to level 12 (Option A), or add a new column (Option B):

**❓ Should referencing tables store:**
- Level 12 quadkey (matches partition key)
- Level 15 quadkey (matches original precision)
- Both levels

---

## REQUIRED INFORMATION

**Please provide:**

1. **Conversion formula**: Exact SQL expression to convert level 15 → level 12
2. **Column strategy**: Single column (A), Dual columns (B), or Computed (C)
3. **Sample data**: Example `main_quadkey` values so we can validate conversion
4. **FK storage**: What level should referencing tables store?

**Example Response Format:**
```
Conversion: main_quadkey_l12 = FLOOR(main_quadkey / 1000)
Strategy: Option B (Dual columns) - add main_quadkey_l12
FK Storage: Level 12 to match partition key
Sample: main_quadkey = 123456789012345 → main_quadkey_l12 = 123456789012
```

---

## NEXT STEPS (ON HOLD)

⏸️ **Waiting for quadkey level conversion specification before proceeding.**

Once quadkey conversion is defined, I will generate:

1. **01_signs_partitioning_migration.sql** - Complete migration script with quadkey conversion
2. **02_signs_partitioning_validation.sql** - Data validation queries
3. **03_signs_fk_table_analysis.sql** - Analysis of referencing tables
4. **04_signs_partitioning_indexes.sql** - All index creation statements

