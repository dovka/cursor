# Timestamp to Date Conversion - Applied

## Fields Changed from TIMESTAMP to DATE

The following 5 fields have been converted from `timestamp` to `date` type in both SQL file versions:

| Field Name | Original Type | New Type | Syntax |
|------------|---------------|----------|--------|
| run_time_created | timestamp | date | `nr.time_created::date` |
| run_end_time | timestamp | date | `nr.end_time::date` |
| step_time_created | timestamp | date | `ns.time_created::date` |
| step_start_time | timestamp | date | `ns.start_time::date` |
| step_end_time | timestamp | date | `ns.end_time::date` |

---

## Reason for Change

This change aligns with the **MV_RUNS_DP_KM table** example provided, which also casts these timestamp fields to date.

---

## Impact

### What Changes
- **Time component is removed** - Only the date portion (YYYY-MM-DD) is preserved
- Example: `2024-12-02 14:35:22` → `2024-12-02`

### What Stays the Same
- All other 48 fields remain unchanged
- The view still returns all 53 fields
- Field names and order are identical

---

## SQL Syntax Used

### Before
```sql
SELECT
    nr.time_created AS run_time_created,
    nr.end_time AS run_end_time,
    ...
    ns.time_created AS step_time_created,
    ns.start_time AS step_start_time,
    ns.end_time AS step_end_time,
    ...
```

### After (Current)
```sql
SELECT
    nr.time_created::date AS run_time_created,
    nr.end_time::date AS run_end_time,
    ...
    ns.time_created::date AS step_time_created,
    ns.start_time::date AS step_start_time,
    ns.end_time::date AS step_end_time,
    ...
```

---

## Files Updated

Both SQL file versions include this change:

✅ `v_nimbus_runs_dp_km_redshift.sql` - Version 1 (VARCHAR statistics)  
✅ `v_nimbus_runs_dp_km_redshift_with_numeric_casting.sql` - Version 2 (numeric statistics)

---

## Validation

After deployment, you can verify the date casting:

```sql
-- Check data types
SELECT 
    run_time_created,
    pg_typeof(run_time_created) as run_time_type,
    run_end_time,
    pg_typeof(run_end_time) as run_end_type,
    step_time_created,
    pg_typeof(step_time_created) as step_time_type,
    step_start_time,
    pg_typeof(step_start_time) as step_start_type,
    step_end_time,
    pg_typeof(step_end_time) as step_end_type
FROM public.v_nimbus_runs_dp_km
LIMIT 1;
```

Expected result: All `pg_typeof` columns should return `date`.

---

## Comparison with Original Postgres View

| Aspect | Postgres View | Redshift View |
|--------|---------------|---------------|
| run_time_created | timestamp with time | date only |
| run_end_time | timestamp with time | date only |
| step_time_created | timestamp with time | date only |
| step_start_time | timestamp with time | date only |
| step_end_time | timestamp with time | date only |

**Trade-off**: You lose the time-of-day information, but gain consistency with the MV_RUNS_DP_KM table format.

---

## Use Cases Impact

### ✅ Still Works Fine
- Date filtering: `WHERE run_time_created >= '2024-01-01'`
- Date grouping: `GROUP BY run_time_created`
- Date comparisons: `WHERE step_end_time > step_start_time`
- Joins on dates

### ⚠️ May Need Adjustment
- Time-of-day analysis (no longer possible)
- Duration calculations in hours/minutes (use date difference in days instead)
- Sorting by exact timestamp (will sort by date only, ties not broken by time)

---

## Summary

✅ **Change applied** to both SQL file versions  
✅ **5 timestamp fields** converted to date  
✅ **Matches MV_RUNS_DP_KM table** format  
✅ **All files** ready for deployment  

**Impact**: Time component is lost, but this aligns with the existing table pattern and is intentional.
