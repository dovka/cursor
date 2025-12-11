# Quick Reference Guide

## ✅ Conversion Status: POSSIBLE

The Aurora Postgres view `v_nimbus_runs_dp_km` can be converted to Redshift with **all 53 fields preserved**.

---

## 📁 Files Generated

| File | Purpose |
|------|---------|
| `v_nimbus_runs_dp_km_redshift.sql` | **Main conversion** - Statistics fields as VARCHAR (exact match) |
| `v_nimbus_runs_dp_km_redshift_with_numeric_casting.sql` | **Alternative** - Statistics fields cast to FLOAT/INT |
| `CONVERSION_SUMMARY.md` | Detailed analysis and assumptions |
| `FIELD_COMPARISON.md` | Field-by-field comparison table |
| `SYNTAX_DIFFERENCES.md` | SQL syntax changes explained |
| `VALIDATION_CHECKLIST.md` | Pre/post deployment validation steps |
| `QUICK_REFERENCE.md` | This file |

---

## 🎯 Which SQL File Should I Use?

### Use `v_nimbus_runs_dp_km_redshift.sql` if:
- ✅ You want an **exact field-type match** to the original Postgres view
- ✅ You're **unsure** which version to choose
- ✅ Downstream queries handle string-to-number conversion
- ✅ You want **minimal risk** of data type incompatibility

### Use `v_nimbus_runs_dp_km_redshift_with_numeric_casting.sql` if:
- ✅ You want to **match the MV_RUNS_DP_KM table** pattern
- ✅ You frequently perform **calculations** on statistics fields
- ✅ You want explicit **NULL handling** for 'NaN' and empty strings
- ✅ You prefer **better query performance** for numeric operations

---

## 🔑 Key Technical Changes

| Change | Why |
|--------|-----|
| Added `WITH NO SCHEMA BINDING` | **CRITICAL** - Required for external Glue tables |
| `->` / `->>` → `JSON_EXTRACT_PATH_TEXT()` | Redshift JSON syntax |
| `RANGE` → `ROWS` in window function | Redshift limitation |
| `now() - '70 days'::interval` → `DATEADD(day, -70, GETDATE())` | Redshift date syntax |
| Added `IS_VALID_JSON()` check | Prevent JSON parsing errors |
| Table names with full catalog path | Glue catalog integration |

---

## ⚠️ Assumptions to Confirm

1. **Table pattern**: `datalake_glue_catalog.db1_shared_dev_a_nimbus__nimbusdb__public_*`
2. **Time filter**: 70 days (keep or change?)
3. **Data types**: VARCHAR or numeric for statistics fields?
4. **Timestamps**: Keep as-is or cast to DATE?
5. **Grants**: `"IAMR:cu-rem-pm-users"` and `quicksight_user`
6. **Schema**: `public`

👉 **See CONVERSION_SUMMARY.md for detailed confirmation checklist**

---

## 🚀 Deployment Steps

### 1. Review & Confirm
- [ ] Read `CONVERSION_SUMMARY.md`
- [ ] Confirm all assumptions
- [ ] Choose SQL version (1 or 2)

### 2. Pre-Deployment Validation
- [ ] Follow `VALIDATION_CHECKLIST.md` steps 1-4
- [ ] Verify source tables exist and have data
- [ ] Test JSON extraction on sample data

### 3. Deploy
```sql
-- Run the selected SQL file in Redshift
-- Example:
\i v_nimbus_runs_dp_km_redshift.sql
```

### 4. Post-Deployment Validation
- [ ] Follow `VALIDATION_CHECKLIST.md` steps 5-9
- [ ] Verify row counts
- [ ] Test sample queries
- [ ] Verify grants

---

## 📊 Field Count

- **Total fields**: 53
- **All preserved**: ✅ Yes
- **Field names match**: ✅ Exactly
- **Field order matches**: ✅ Exactly

---

## 🔍 Quick Syntax Reference

### Late Binding View (CRITICAL)
```sql
-- Postgres
CREATE OR REPLACE VIEW public.v_nimbus_runs_dp_km AS
SELECT ...;

-- Redshift (REQUIRED for external tables)
CREATE OR REPLACE VIEW public.v_nimbus_runs_dp_km AS
SELECT ...
WITH NO SCHEMA BINDING;
```

**Note**: `WITH NO SCHEMA BINDING` goes at the END

### JSON Extraction
```sql
-- Postgres
(metadata_json -> 'resources_tags') ->> 'RemCMCellId'

-- Redshift
JSON_EXTRACT_PATH_TEXT(metadata_json, 'resources_tags', 'RemCMCellId', true)
```

### Date Filter
```sql
-- Postgres
WHERE time_created >= (now() - '70 days'::interval)

-- Redshift
WHERE time_created >= DATEADD(day, -70, GETDATE())
```

### Window Function
```sql
-- Postgres
RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING

-- Redshift
ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
```

👉 **See SYNTAX_DIFFERENCES.md for complete syntax guide**

---

## 🆘 Troubleshooting

### Issue: "Table does not exist"
**Fix**: Verify table naming pattern in your Glue catalog. Update table names in SQL file.

### Issue: "JSON parsing error"
**Fix**: Ensure `IS_VALID_JSON()` check is present in WHERE clause.

### Issue: "RANGE not supported"
**Fix**: Already fixed - using ROWS instead of RANGE.

### Issue: "Grant failed"
**Fix**: Verify role names exist in your Redshift cluster. Update grant statements.

### Issue: Row count mismatch
**Check**: 
- Time filter (70 days) may capture different data due to timezone differences
- JSON validation filter may exclude invalid records
- Both are expected and correct behavior

---

## 📞 Support Files

- **Detailed analysis**: `CONVERSION_SUMMARY.md`
- **Field comparison**: `FIELD_COMPARISON.md`
- **Syntax help**: `SYNTAX_DIFFERENCES.md`
- **Validation**: `VALIDATION_CHECKLIST.md`

---

## ✨ Summary

**Bottom Line**: The conversion is straightforward and all fields are preserved. The main decision is whether to keep statistics fields as VARCHAR (exact match) or cast to numeric (better performance).

**Recommended**: Start with Version 1 (VARCHAR) for exact compatibility, then migrate to Version 2 (numeric) if needed based on usage patterns.
