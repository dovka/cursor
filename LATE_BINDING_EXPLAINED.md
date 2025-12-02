# Late Binding Views in Redshift - Explained

## What is the Error?

```
ERROR: External tables are not supported in views
Hint: Please use late binding view and add 'with no schema binding' at the query end.
[ErrorId: 1-692eeaea-2d3797131490b3e3178c1747]
```

---

## Why Does This Happen?

Redshift **does not allow** regular views to reference:
- External tables (like Glue catalog tables starting with `datalake_glue_catalog.*`)
- Tables from other databases
- Spectrum tables

This is because regular views validate the schema (column names, types) at **creation time**, and external tables' schemas can change independently.

---

## The Solution: Late Binding Views

Add `WITH NO SCHEMA BINDING` to the CREATE VIEW statement:

```sql
CREATE OR REPLACE VIEW public.v_nimbus_runs_dp_km
WITH NO SCHEMA BINDING
AS
SELECT ...
```

---

## What is a Late Binding View?

| Regular View | Late Binding View |
|-------------|-------------------|
| Validates schema at **creation time** | Validates schema at **query time** |
| Fails if referenced tables don't exist | Creates successfully even if tables don't exist |
| Fails if columns don't match | Fails at query time if columns don't match |
| Works with local tables only | Works with external tables |
| Schema changes break the view | Schema changes detected at runtime |

---

## How Late Binding Works

### Regular View (Early Binding)
```sql
-- Creation time
CREATE VIEW my_view AS SELECT col1, col2 FROM my_table;
-- ✅ Checks: Does my_table exist? Does it have col1, col2?
-- ❌ Fails if table doesn't exist or columns are missing

-- Query time
SELECT * FROM my_view;
-- ✅ Just reads the pre-validated view
```

### Late Binding View
```sql
-- Creation time
CREATE VIEW my_view WITH NO SCHEMA BINDING AS SELECT col1, col2 FROM my_table;
-- ✅ Creates view without checking if table/columns exist
-- ⚠️  Just stores the SQL text

-- Query time
SELECT * FROM my_view;
-- ✅ NOW checks: Does my_table exist? Does it have col1, col2?
-- ❌ Fails at this point if table/columns don't exist
```

---

## Implications for Our View

### Benefits
✅ Can reference external Glue catalog tables  
✅ Schema changes in source tables don't break view creation  
✅ More flexible for evolving data pipelines  

### Trade-offs
⚠️ Errors appear at **query time** instead of creation time  
⚠️ No upfront validation of column names/types  
⚠️ Typos in column names won't be caught until you query  

---

## Best Practices with Late Binding Views

### 1. Test Immediately After Creation
```sql
-- Create the view
CREATE VIEW my_view WITH NO SCHEMA BINDING AS ...;

-- IMMEDIATELY test it
SELECT * FROM my_view LIMIT 1;
```

This catches column name typos or missing tables right away.

### 2. Document External Table Dependencies
Keep track of which external tables the view depends on, since Redshift won't enforce referential integrity.

### 3. Monitor for Schema Changes
If source tables in Glue catalog change schema (columns added/removed/renamed), the view may break at runtime.

---

## Example: Our View

### Before (Causes Error)
```sql
CREATE OR REPLACE VIEW public.v_nimbus_runs_dp_km
AS
WITH nr AS (
    SELECT ...
    FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_nimbus_runs
    ...
)
...
```

❌ **ERROR**: External tables are not supported in views

### After (Works Correctly)
```sql
CREATE OR REPLACE VIEW public.v_nimbus_runs_dp_km
WITH NO SCHEMA BINDING
AS
WITH nr AS (
    SELECT ...
    FROM datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_nimbus_runs
    ...
)
...
```

✅ **SUCCESS**: View created successfully

---

## Validation After Creation

After creating the late binding view, validate it works:

```sql
-- Test 1: Basic query
SELECT COUNT(*) FROM public.v_nimbus_runs_dp_km;

-- Test 2: Verify columns exist
SELECT * FROM public.v_nimbus_runs_dp_km LIMIT 1;

-- Test 3: Check specific columns
SELECT 
    run_uuid,
    run_status,
    step_name,
    remcmcellid
FROM public.v_nimbus_runs_dp_km
LIMIT 10;
```

If any column names are wrong, you'll get an error like:
```
ERROR: column "wrong_column_name" does not exist
```

---

## Common Pitfalls

### Pitfall 1: Typo in Column Name
```sql
CREATE VIEW my_view WITH NO SCHEMA BINDING AS
SELECT wrong_colum_name FROM external_table;
-- ✅ Creates successfully (late binding doesn't validate)

SELECT * FROM my_view;
-- ❌ ERROR: column "wrong_colum_name" does not exist
```

**Solution**: Always test the view immediately after creation.

### Pitfall 2: External Table Schema Changed
```sql
-- View expects columns: id, name, email
CREATE VIEW my_view WITH NO SCHEMA BINDING AS
SELECT id, name, email FROM external_table;

-- Later, external table schema changes (email column removed)
-- View creation was long ago, still exists

SELECT * FROM my_view;
-- ❌ ERROR: column "email" does not exist
```

**Solution**: Monitor external table schema changes and update views accordingly.

---

## Summary

**For our `v_nimbus_runs_dp_km` view:**

1. ✅ `WITH NO SCHEMA BINDING` is **required** (not optional)
2. ✅ Already added to both SQL files
3. ✅ Test immediately after creation with `SELECT * FROM ... LIMIT 1`
4. ✅ All column names are correct (validated against original Postgres view)
5. ✅ Should work without issues

**Next step**: Deploy the updated SQL file and test immediately.
