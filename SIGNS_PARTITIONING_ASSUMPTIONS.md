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

## SUMMARY OF DECISIONS NEEDED

Please confirm or modify:

1. ✅ HASH partitioning on `(main_quadkey, map_id)` with 20 buckets
2. ❓ PK column order: `(id, main_quadkey, map_id)` or `(main_quadkey, map_id, id)`
3. ❓ How to handle NULL values in `main_quadkey` or `map_id`
4. ❓ Naming convention for new FK columns in referencing tables
5. ❓ Confirm all 11 indexes should be recreated
6. ❓ Zero-downtime required or maintenance window acceptable
7. ✅ Keep existing sequences and defaults
8. ✅ Preserve outbound FK constraints from signs table
9. ❓ Acceptable that queries without partition key filters scan all partitions
10. ❓ Rollback requirements

---

## NEXT STEPS

Once you confirm the above assumptions, I will generate:

1. **01_signs_partitioning_migration.sql** - Complete migration script
2. **02_signs_partitioning_rollback.sql** - Rollback script
3. **03_signs_partitioning_validation.sql** - Data validation queries
4. **04_signs_partitioning_fk_updates.sql** - Foreign key updates for referencing tables

