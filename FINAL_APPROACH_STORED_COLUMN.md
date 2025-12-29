# Final Approach: Stored Column for Level 12 Quadkey

## Test Results Summary

❌ **Tested and FAILED:**
```sql
-- Option 1: Column in PK, expression in PARTITION
PRIMARY KEY (id, main_quadkey, map_id)
PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)
→ ERROR: PRIMARY KEY constraints cannot be used when partition keys include expressions

-- Option 2: Expression in PK
PRIMARY KEY (id, (FLOOR(main_quadkey / 1000)), map_id)
PARTITION BY HASH (FLOOR(main_quadkey / 1000), map_id)
→ ERROR: Cannot have expression inside PRIMARY KEY constraint
```

## ✅ Required Solution: Stored Column

PostgreSQL **requires** a physical column (not expression) for both PK and partition key.

---

## Schema Design

### Partitioned Signs Table

```sql
CREATE TABLE signs_new (
    -- Primary key columns
    id BIGINT NOT NULL,
    
    -- Quadkey columns (both levels stored)
    main_quadkey INTEGER NOT NULL,      -- Original level 15 (or 16?)
    main_quadkey_l12 INTEGER NOT NULL,  -- Computed level 12 for partitioning
    
    -- Map ID
    map_id INTEGER NOT NULL,
    
    -- All other existing columns (36 total columns)
    time_created TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
    external_id BIGINT,
    location GEOMETRY(PointZ) NOT NULL,
    location_covariance_x DOUBLE PRECISION[] NOT NULL,
    location_covariance_y DOUBLE PRECISION[] NOT NULL,
    location_covariance_z DOUBLE PRECISION[] NOT NULL,
    system_type_id INTEGER NOT NULL,
    traffic_sign_type_id INTEGER NOT NULL,
    width DOUBLE PRECISION NOT NULL,
    height DOUBLE PRECISION NOT NULL,
    width_std DOUBLE PRECISION NOT NULL,
    height_std DOUBLE PRECISION NOT NULL,
    edge_id INTEGER,
    map_uuid UUID,
    edge_s DOUBLE PRECISION,
    uuid UUID,
    metadata_json CHARACTER VARYING,
    map_uuids UUID[],
    has_back_of_sign BOOLEAN,
    orientation DOUBLE PRECISION[],
    base_map_uuid UUID,
    cell_uuid UUID,
    last_run_uuid UUID,
    has_same_sign_on_back BOOLEAN,
    geometry_lla GEOGRAPHY(PointZ,4326),
    to_delete BOOLEAN,
    orientation_std DOUBLE PRECISION,
    visibility DOUBLE PRECISION,
    existence_confidence DOUBLE PRECISION,
    type_confidence DOUBLE PRECISION,
    total_num_obs INTEGER,
    covariance_distance DOUBLE PRECISION,
    sign_category_enum sign_category_enum,
    date_last_seen DATE,
    sign_metadata_json JSONB,
    topo_db_id INTEGER
    
) PARTITION BY HASH (main_quadkey_l12, map_id);
```

### Primary Key (Created AFTER partitions)

```sql
ALTER TABLE signs_new 
ADD CONSTRAINT signs_pkey 
PRIMARY KEY (id, main_quadkey_l12, map_id);
```

### 20 Partitions

```sql
CREATE TABLE signs_p00 PARTITION OF signs_new 
    FOR VALUES WITH (MODULUS 20, REMAINDER 0);
CREATE TABLE signs_p01 PARTITION OF signs_new 
    FOR VALUES WITH (MODULUS 20, REMAINDER 1);
-- ... through ...
CREATE TABLE signs_p19 PARTITION OF signs_new 
    FOR VALUES WITH (MODULUS 20, REMAINDER 19);
```

### Indexes (Created AFTER partitions)

```sql
-- Primary key index (automatic with PK constraint)

-- Additional indexes (all existing ones)
CREATE INDEX idx_signs_geometry_lla 
    ON signs_new USING GIST (geometry_lla);
    
CREATE INDEX ix_signs_base_map_uuid 
    ON signs_new (base_map_uuid);
    
CREATE INDEX ix_signs_cell_uuid 
    ON signs_new (cell_uuid);
    
CREATE INDEX ix_signs_edge_id 
    ON signs_new (edge_id);
    
CREATE INDEX ix_signs_edge_s 
    ON signs_new (edge_s);
    
CREATE INDEX ix_signs_external_id 
    ON signs_new (external_id);
    
CREATE INDEX ix_signs_main_quadkey 
    ON signs_new (main_quadkey);
    
CREATE INDEX ix_signs_map_id 
    ON signs_new (map_id);
    
CREATE INDEX ix_signs_topo_db_id 
    ON signs_new (topo_db_id);
    
CREATE INDEX ix_signs_uuid 
    ON signs_new (uuid);
    
CREATE INDEX signs_base_map_uuid_geometry_lla_idx 
    ON signs_new USING GIST (base_map_uuid, geometry_lla);

-- Optional: Index on partition key for query optimization
CREATE INDEX ix_signs_partition_key 
    ON signs_new (main_quadkey_l12, map_id);
```

---

## Data Migration

### Migration Query

```sql
INSERT INTO signs_new (
    id, main_quadkey, main_quadkey_l12, map_id, 
    time_created, external_id, location, location_covariance_x,
    location_covariance_y, location_covariance_z, system_type_id,
    traffic_sign_type_id, width, height, width_std, height_std,
    edge_id, map_uuid, edge_s, uuid, metadata_json, map_uuids,
    has_back_of_sign, orientation, base_map_uuid, cell_uuid,
    last_run_uuid, has_same_sign_on_back, geometry_lla, to_delete,
    orientation_std, visibility, existence_confidence, type_confidence,
    total_num_obs, covariance_distance, sign_category_enum,
    date_last_seen, sign_metadata_json, topo_db_id
)
SELECT 
    id,
    COALESCE(main_quadkey, 0) as main_quadkey,  -- Set to 0 if NULL
    COALESCE(FLOOR(main_quadkey / 1000), 0) as main_quadkey_l12,  -- CONVERSION FORMULA
    map_id,
    -- ... all other columns ...
FROM signs
WHERE map_id IS NOT NULL;  -- Only migrate rows with map_id
```

**Key Points:**
- ⚠️ **Conversion formula `FLOOR(main_quadkey / 1000)` still needs verification!**
- Only migrate rows where `map_id IS NOT NULL`
- Set `main_quadkey = 0` if NULL (as specified)

---

## Foreign Key Updates

All 10 referencing tables need updates. Two options:

### Option A: Store Level 12 (Matches Partition Key)

Referencing tables store level 12 to match the PK:

```sql
ALTER TABLE sign_to_edge_association
ADD COLUMN sign_main_quadkey_l12 INTEGER,
ADD COLUMN sign_map_id INTEGER;

-- Backfill
UPDATE sign_to_edge_association ref
SET sign_main_quadkey_l12 = s.main_quadkey_l12,
    sign_map_id = s.map_id
FROM signs_new s
WHERE ref.sign_id = s.id;

-- Set NOT NULL
ALTER TABLE sign_to_edge_association
ALTER COLUMN sign_main_quadkey_l12 SET NOT NULL,
ALTER COLUMN sign_map_id SET NOT NULL;

-- Drop old FK
ALTER TABLE sign_to_edge_association
DROP CONSTRAINT sign_to_edge_association_sign_id_fkey;

-- Add new FK
ALTER TABLE sign_to_edge_association
ADD CONSTRAINT sign_to_edge_association_sign_id_fkey
FOREIGN KEY (sign_id, sign_main_quadkey_l12, sign_map_id)
REFERENCES signs_new(id, main_quadkey_l12, map_id)
DEFERRABLE;
```

**Column naming question:** Since you chose Option B naming (just `main_quadkey`, `map_id`), but these might conflict with existing columns, we need to check each table.

### Option B: Store Both Levels (If Needed)

If referencing tables need full precision for analysis:

```sql
ALTER TABLE sign_to_edge_association
ADD COLUMN sign_main_quadkey INTEGER,      -- Level 15
ADD COLUMN sign_main_quadkey_l12 INTEGER,  -- Level 12 (for FK)
ADD COLUMN sign_map_id INTEGER;
```

---

## Query Patterns

### Guaranteed Partition Pruning ✅

```sql
-- Query by level 12 quadkey
SELECT * FROM signs_new
WHERE main_quadkey_l12 = 1656756
  AND map_id = 42;
-- ✅ Will prune to 1 partition
```

### Query by Level 15 (Original)

**Option 1:** Application computes level 12
```sql
-- Application computes: quadkey_l12 = FLOOR(main_quadkey / 1000)
SELECT * FROM signs_new
WHERE main_quadkey = 1656756156
  AND main_quadkey_l12 = 1656756  -- Enables partition pruning!
  AND map_id = 42;
-- ✅ Will prune to 1 partition
```

**Option 2:** Query without level 12
```sql
SELECT * FROM signs_new
WHERE main_quadkey = 1656756156
  AND map_id = 42;
-- ❌ Will scan ALL 20 partitions (no partition pruning)
```

### Application Helper Function

```python
def get_quadkey_l12(quadkey_l15):
    """Convert level 15 quadkey to level 12"""
    if quadkey_l15 is None:
        return 0
    # TODO: Verify this formula is correct!
    return quadkey_l15 // 1000

def query_signs_by_quadkey(main_quadkey, map_id):
    quadkey_l12 = get_quadkey_l12(main_quadkey)
    
    query = """
        SELECT * FROM signs
        WHERE main_quadkey = %s
          AND main_quadkey_l12 = %s
          AND map_id = %s
    """
    return execute(query, (main_quadkey, quadkey_l12, map_id))
```

---

## Storage Overhead

**Additional storage per row:**
- `main_quadkey_l12`: 4 bytes (INTEGER)
- **Total overhead:** ~4 bytes per row

For a table with millions of rows:
- 10 million rows × 4 bytes = 40 MB
- 100 million rows × 4 bytes = 400 MB

**Negligible compared to benefits of partitioning.**

---

## Advantages of This Approach

✅ **Guaranteed to work** - No PostgreSQL limitations  
✅ **Predictable partition pruning** - When querying by `main_quadkey_l12`  
✅ **Clean PK structure** - Standard columns, no expressions  
✅ **FK compatibility** - Straightforward foreign key constraints  
✅ **Can query either level** - Original or level 12  
✅ **Can create index on partition key** - For additional optimization  

---

## Trade-offs

⚠️ **Storage overhead** - Additional 4 bytes per row  
⚠️ **Must maintain both columns** - Application responsibility  
⚠️ **Query changes** - Include `main_quadkey_l12` for pruning  
⚠️ **FK updates required** - All 10 referencing tables need changes  

---

## Critical: Conversion Formula Verification

**STILL NEED TO CONFIRM:** Is `FLOOR(main_quadkey / 1000)` correct?

Your sample quadkeys (~1.65 billion) suggest:
- **NOT** traditional base-4 quadkey strings
- Possibly level 16 tile indices
- Or different encoding

**Before migration, please:**
1. Run the analysis query to compare conversion methods
2. Verify with sample data that conversion produces valid level 12 values
3. Check existing codebase for conversion functions

See `QUADKEY_FORMAT_ANALYSIS.md` for detailed analysis.

---

## Next Steps

### 1. Confirm Conversion Formula ❓

Please provide or verify:
```sql
-- Is this correct?
main_quadkey_l12 = FLOOR(main_quadkey / 1000)

-- Or should it be?
main_quadkey_l12 = FLOOR(main_quadkey / 65536 / 16) * 4096 + 
                   FLOOR((main_quadkey % 65536) / 16)

-- Or something else?
```

### 2. Check Referencing Tables for Column Conflicts

Run the analysis script to see which tables already have `main_quadkey` or `map_id` columns:
```bash
psql -d your_database -f analyze_referencing_tables.sql
```

### 3. Approve Schema Design

Confirm:
- ✅ Stored column approach is acceptable
- ✅ ~4 bytes per row overhead is acceptable
- ✅ Application can provide both quadkey levels in queries
- ✅ FK updates for 10 tables is acceptable

### 4. Generate Migration Scripts

Once confirmed, I'll generate:
1. **01_create_partitioned_table.sql** - Table + 20 partitions
2. **02_create_indexes.sql** - All 11+ indexes
3. **03_migrate_data.sql** - Data migration with conversion
4. **04_update_foreign_keys.sql** - Updates for 10 referencing tables
5. **05_cutover.sql** - Rename operations
6. **06_validation.sql** - Data integrity checks

---

## Summary

**Required structure** (PostgreSQL limitation):
```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey INTEGER NOT NULL,      -- Level 15
    main_quadkey_l12 INTEGER NOT NULL,  -- Level 12 - REQUIRED!
    map_id INTEGER NOT NULL,
    -- ... other columns ...
    PRIMARY KEY (id, main_quadkey_l12, map_id)
) PARTITION BY HASH (main_quadkey_l12, map_id);
```

**This is the ONLY way to partition with a transformed key in PostgreSQL.**

Ready to proceed once you confirm the conversion formula! 🚀
