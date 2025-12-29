# Analysis: Local Unique Index on ID and Foreign Key Support

## Your Question

Can we use local unique indexes on `id` (per partition) to support existing foreign keys that reference `signs(id)`?

---

## Short Answer: ❌ NO

**PostgreSQL does NOT support foreign keys referencing locally unique columns in partitioned tables.**

Foreign keys require a **global uniqueness constraint** that spans all partitions, which means the constraint must include all partition key columns.

---

## Detailed Explanation

### What Are Local Unique Indexes?

You can create a unique index on `id` within each partition:

```sql
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey_l12 INTEGER NOT NULL,
    map_id INTEGER NOT NULL,
    -- ... other columns ...
    -- NO primary key at parent level
) PARTITION BY HASH (main_quadkey_l12, map_id);

-- Create partitions
CREATE TABLE signs_p00 PARTITION OF signs_new ...;
CREATE TABLE signs_p01 PARTITION OF signs_new ...;
-- ... etc

-- Create UNIQUE index on each partition
CREATE UNIQUE INDEX signs_p00_id_idx ON signs_p00 (id);
CREATE UNIQUE INDEX signs_p01_id_idx ON signs_p01 (id);
-- ... for each partition
```

**This provides:**
- ✅ Uniqueness of `id` within each partition
- ❌ **NO global uniqueness** across all partitions
- Two different partitions could theoretically have the same `id`

### Can Foreign Keys Reference This?

**Attempt to create FK:**
```sql
ALTER TABLE sign_to_edge_association
ADD CONSTRAINT sign_to_edge_association_sign_id_fkey
FOREIGN KEY (sign_id) REFERENCES signs_new(id);
```

**Result:**
```
ERROR: there is no unique constraint matching given keys for referenced table "signs_new"
```

**Why it fails:**
- Foreign keys require a **global** unique constraint
- Local unique indexes (per partition) don't provide global uniqueness
- PostgreSQL cannot enforce the FK across all partitions

---

## PostgreSQL's Limitation

From PostgreSQL documentation:

> "A PRIMARY KEY constraint on a partitioned table must include all the partition key columns. The same applies to UNIQUE constraints."

**Consequence:**
- To have a globally unique constraint on `id`, you must create: `UNIQUE (id, main_quadkey_l12, map_id)`
- But this doesn't guarantee `id` alone is unique (different quadkey/map combinations could have same `id`)
- Wait, actually if `id` is globally unique in your data, then having it in a composite unique constraint with other columns still guarantees its uniqueness

**Actually, let me reconsider:**

If you have:
```sql
PRIMARY KEY (id, main_quadkey_l12, map_id)
```

And `id` is naturally unique in your application (like a sequence), then:
- The PK ensures uniqueness of the combination
- But since `id` is unique anyway, the PK effectively enforces `id` uniqueness
- **HOWEVER**, foreign keys from other tables would still need to reference all three columns

---

## Three Scenarios Compared

### Scenario 1: Composite PK with All Columns (ONLY OPTION THAT WORKS)

```sql
-- Parent table
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey_l12 INTEGER NOT NULL,
    map_id INTEGER NOT NULL,
    PRIMARY KEY (id, main_quadkey_l12, map_id)
) PARTITION BY HASH (main_quadkey_l12, map_id);

-- Child table FK
ALTER TABLE sign_to_edge_association
ADD COLUMN sign_main_quadkey_l12 INTEGER,
ADD COLUMN sign_map_id INTEGER,
ADD CONSTRAINT fk_sign
FOREIGN KEY (sign_id, sign_main_quadkey_l12, sign_map_id) 
REFERENCES signs_new(id, main_quadkey_l12, map_id);
```

**Result:**
- ✅ Works with PostgreSQL
- ✅ Foreign key enforced
- ❌ Child tables need extra columns
- ❌ All FK queries must join on 3 columns

---

### Scenario 2: Local Unique Indexes (DOES NOT WORK)

```sql
-- Parent table
CREATE TABLE signs_new (
    id BIGINT NOT NULL,
    main_quadkey_l12 INTEGER NOT NULL,
    map_id INTEGER NOT NULL
    -- NO global PK or UNIQUE constraint
) PARTITION BY HASH (main_quadkey_l12, map_id);

-- Unique per partition
CREATE UNIQUE INDEX ON signs_p00 (id);
CREATE UNIQUE INDEX ON signs_p01 (id);
-- ... etc

-- Child table FK (ATTEMPT)
ALTER TABLE sign_to_edge_association
ADD CONSTRAINT fk_sign
FOREIGN KEY (sign_id) REFERENCES signs_new(id);  -- FAILS!
```

**Result:**
- ❌ PostgreSQL rejects the FK
- ❌ No global uniqueness guarantee
- ❌ Cannot enforce referential integrity

---

### Scenario 3: No FK Constraints (APPLICATION-LEVEL ONLY)

```sql
-- Parent table with local unique indexes
CREATE TABLE signs_new (...) PARTITION BY HASH (...);
CREATE UNIQUE INDEX ON signs_p00 (id);
-- ... etc

-- Child table - NO FOREIGN KEY
CREATE TABLE sign_to_edge_association (
    sign_id BIGINT NOT NULL,  -- Just a column, no FK
    ...
);
```

**Result:**
- ✅ Works technically
- ❌ No database-level referential integrity
- ❌ Application must ensure references are valid
- ❌ Can have orphaned records
- ❌ Cascading deletes/updates don't work
- ❌ Not recommended for production

---

## Why This Limitation Exists

### The Technical Reason

When you insert/update a foreign key, PostgreSQL must verify the referenced row exists:

```sql
-- When inserting into child table:
INSERT INTO sign_to_edge_association (sign_id, edge_id) 
VALUES (12345, 67890);

-- PostgreSQL must verify:
-- Does a row with id=12345 exist in signs_new?
```

**With partitioning:**
- Without knowing the partition, PostgreSQL would need to check ALL partitions
- With 20 partitions, that's 20 index lookups for every FK check
- This is expensive and defeats the purpose of partitioning

**With composite FK:**
```sql
INSERT INTO sign_to_edge_association 
    (sign_id, sign_main_quadkey_l12, sign_map_id, edge_id) 
VALUES (12345, 1656756, 42, 67890);

-- PostgreSQL can determine the partition:
-- HASH(1656756, 42) → partition 7
-- Check only partition 7 for (12345, 1656756, 42)
-- One index lookup!
```

This is why PostgreSQL requires partition keys in the FK.

---

## Impact on Your 10 Referencing Tables

All 10 tables that currently have FK to `signs(id)` MUST be updated:

### Current State
```sql
CREATE TABLE sign_to_edge_association (
    association_id SERIAL PRIMARY KEY,
    sign_id BIGINT NOT NULL,
    edge_id INTEGER NOT NULL,
    FOREIGN KEY (sign_id) REFERENCES signs(id)
);
```

### Required New State
```sql
CREATE TABLE sign_to_edge_association (
    association_id SERIAL PRIMARY KEY,
    sign_id BIGINT NOT NULL,
    sign_main_quadkey_l12 INTEGER NOT NULL,  -- NEW
    sign_map_id INTEGER NOT NULL,             -- NEW
    edge_id INTEGER NOT NULL,
    FOREIGN KEY (sign_id, sign_main_quadkey_l12, sign_map_id) 
    REFERENCES signs(id, main_quadkey_l12, map_id)
);
```

**Migration for each table:**
1. Add new columns
2. Backfill from signs table
3. Set NOT NULL
4. Drop old FK constraint
5. Add new composite FK constraint
6. Update application queries to include new columns in JOINs

---

## Alternative: Drop All Foreign Keys

If FK maintenance is too complex, you could:

### Option A: Remove FK Constraints
```sql
-- Drop all FK constraints to signs table
-- Rely on application-level integrity
-- Use periodic validation queries
```

**Pros:**
- ✅ No need to update referencing tables
- ✅ No need to change application queries
- ✅ Simpler migration

**Cons:**
- ❌ No database-level referential integrity
- ❌ Possible orphaned records
- ❌ No cascading deletes/updates
- ❌ Data quality issues over time
- ❌ Not recommended for production systems

### Option B: Use Triggers Instead
```sql
-- Create trigger on referencing tables
-- Manually validate references exist
```

**Pros:**
- ✅ Can validate with just sign_id
- ✅ Some integrity enforcement

**Cons:**
- ❌ Complex to maintain
- ❌ Performance overhead
- ❌ Doesn't provide same guarantees as FKs
- ❌ No automatic index creation
- ❌ Not recommended

---

## Recommendation

**You MUST use composite foreign keys.** There is no alternative in PostgreSQL that maintains referential integrity.

### Migration Impact Summary

**For signs table:**
- Add `main_quadkey_l12` column
- Use composite PK: `(id, main_quadkey_l12, map_id)`

**For each of 10 referencing tables:**
1. Add 2 columns: `sign_main_quadkey_l12`, `sign_map_id`
2. Backfill data:
   ```sql
   UPDATE referencing_table ref
   SET sign_main_quadkey_l12 = s.main_quadkey_l12,
       sign_map_id = s.map_id
   FROM signs s
   WHERE ref.sign_id = s.id;
   ```
3. Update FK constraint
4. Update application queries:
   ```sql
   -- Old query
   SELECT * FROM referencing_table r
   JOIN signs s ON r.sign_id = s.id;
   
   -- New query
   SELECT * FROM referencing_table r
   JOIN signs s ON r.sign_id = s.id 
                AND r.sign_main_quadkey_l12 = s.main_quadkey_l12
                AND r.sign_map_id = s.map_id;
   ```

**Storage overhead:**
- Per referencing table row: ~8 bytes (INTEGER + INTEGER)
- If referencing tables are much smaller than signs: minimal impact

---

## Can We Minimize FK Updates?

### Check Which Tables Already Have These Columns

Some referencing tables might already have `map_id` or `main_quadkey`:

```sql
-- Run this to check
SELECT 
    table_name,
    column_name
FROM information_schema.columns
WHERE table_name IN (
    'alternating_lane_sign_association',
    'dp_stop_point_group_to_tfl_associations',
    'dp_stop_point_ra_association',
    'dp_stop_point_sign_association',
    'dp_stop_point_tlf_association',
    'ltwa_dp_stop_point_to_tfl_association',
    'sign_alternative_observation_associations',
    'sign_supplementary_type_associations',
    'sign_to_dp_association',
    'sign_to_edge_association'
)
AND column_name IN ('main_quadkey', 'main_quadkey_l12', 'map_id')
ORDER BY table_name, column_name;
```

If some tables already have these columns, migration is easier.

---

## Summary

| Approach | FK Support | Referential Integrity | Complexity |
|----------|------------|----------------------|------------|
| **Composite PK + Composite FK** | ✅ Yes | ✅ Full | High (must update 10 tables) |
| **Local Unique Indexes** | ❌ No | ❌ None | N/A (doesn't work) |
| **No FK Constraints** | ❌ No | ❌ Application-only | Low (risky) |

**Only the first approach works with PostgreSQL partitioning while maintaining data integrity.**

---

## Answer to Your Question

**Q: If we go for the local unique index on ID, will it support the existing FKs pointing to signs(id)?**

**A: ❌ NO**

- PostgreSQL requires foreign keys to reference globally unique constraints
- Local unique indexes (per partition) do not provide global uniqueness
- FKs will fail with error: "there is no unique constraint matching given keys"
- You MUST use composite PK `(id, main_quadkey_l12, map_id)` and update all 10 referencing tables with composite FKs

**This is a fundamental PostgreSQL limitation with partitioned tables.**

The only way to maintain foreign key constraints is to:
1. Include partition keys in the PK of signs table
2. Add those same columns to all referencing tables
3. Update all FK constraints to be composite

There is no workaround that preserves database-enforced referential integrity.
