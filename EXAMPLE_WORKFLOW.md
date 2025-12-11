# Example Migration Workflow

This document shows a complete end-to-end example of migrating QuickSight resources from Aurora to Redshift.

## Scenario

**Company:** Acme Analytics
**Current Setup:**
- 1 Aurora PostgreSQL data source
- 5 datasets using Aurora
- 10 analyses using those datasets
- 8 dashboards published from those analyses

**Goal:** Migrate everything to Redshift while maintaining business continuity

**Strategy:** Clone mode (safer for production)

---

## Step 1: Initial Assessment

### List Current Resources

```bash
python scripts/list_resources.py \
  --aws-account-id 123456789012 \
  --region us-east-1 \
  --export inventory_pre_migration.json
```

**Output:**
```
================================================================================
QuickSight Resources Using Aurora PostgreSQL
================================================================================

📊 Found 1 Aurora/PostgreSQL Data Source(s):
--------------------------------------------------------------------------------

  ID: aurora-prod-db
  Name: Production Aurora Database
  Type: AURORA_POSTGRESQL
  ARN: arn:aws:quicksight:us-east-1:123456789012:datasource/aurora-prod-db
  Host: prod-aurora.cluster-abc123.us-east-1.rds.amazonaws.com
  Database: analytics

  📦 Datasets using this data source (5):
    - Sales Data (ID: sales-dataset)
      📈 Analyses (2):
        * Sales Dashboard Analysis (ID: sales-analysis)
        * Regional Sales Analysis (ID: regional-sales-analysis)
      📊 Dashboards (2):
        * Sales Dashboard (ID: sales-dashboard)
        * Regional Dashboard (ID: regional-dashboard)
    
    - Customer Data (ID: customer-dataset)
      📈 Analyses (1):
        * Customer Analysis (ID: customer-analysis)
      📊 Dashboards (1):
        * Customer Dashboard (ID: customer-dashboard)
    
    - Product Data (ID: product-dataset)
      📈 Analyses (2):
        * Product Performance (ID: product-analysis)
        * Inventory Analysis (ID: inventory-analysis)
      📊 Dashboards (2):
        * Product Dashboard (ID: product-dashboard)
        * Inventory Dashboard (ID: inventory-dashboard)
    
    - Marketing Data (ID: marketing-dataset)
      📈 Analyses (3):
        * Campaign Analysis (ID: campaign-analysis)
        * ROI Analysis (ID: roi-analysis)
        * Attribution Analysis (ID: attribution-analysis)
      📊 Dashboards (2):
        * Marketing Dashboard (ID: marketing-dashboard)
        * ROI Dashboard (ID: roi-dashboard)
    
    - Finance Data (ID: finance-dataset)
      📈 Analyses (2):
        * P&L Analysis (ID: pl-analysis)
        * Budget Analysis (ID: budget-analysis)
      📊 Dashboards (1):
        * Finance Dashboard (ID: finance-dashboard)

================================================================================
```

---

## Step 2: Validate Redshift Schema

### Connect to Aurora and Redshift

```bash
# Aurora
psql -h prod-aurora.cluster-abc123.us-east-1.rds.amazonaws.com \
     -U admin -d analytics -p 5432

# Redshift
psql -h prod-redshift.abc123.us-east-1.redshift.amazonaws.com \
     -U admin -d analytics -p 5439
```

### Compare Schemas

```sql
-- Run on both Aurora and Redshift
SELECT 
    table_schema,
    table_name,
    column_name,
    data_type,
    ordinal_position
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;
```

**Verify:** ✅ Schemas match perfectly

---

## Step 3: Prepare Configuration

### Create Redshift Configuration

```bash
cp config/redshift_config.example.json config/redshift_config.json
nano config/redshift_config.json
```

**Content:**
```json
{
  "data_source_id": "redshift-prod-db",
  "name": "Production Redshift Cluster",
  "cluster_id": "prod-redshift-cluster",
  "host": "prod-redshift.abc123.us-east-1.redshift.amazonaws.com",
  "port": 5439,
  "database": "analytics",
  "username": "quicksight_user",
  "password": "SecurePassword123!",
  "vpc_connection_arn": "arn:aws:quicksight:us-east-1:123456789012:vpcConnection/vpc-12345"
}
```

---

## Step 4: Create Redshift Data Source

```bash
python scripts/create_redshift_datasource.py \
  --aws-account-id 123456789012 \
  --region us-east-1 \
  --config config/redshift_config.json \
  --test
```

**Output:**
```
✅ Successfully created Redshift data source: redshift-prod-db
   ARN: arn:aws:quicksight:us-east-1:123456789012:datasource/redshift-prod-db
   Status: 200

⏳ Waiting 5 seconds for data source initialization...
✅ Data source connection test successful!
```

---

## Step 5: Migrate Datasets (Clone Mode)

```bash
python scripts/migrate_datasets.py \
  --aws-account-id 123456789012 \
  --region us-east-1 \
  --source-id aurora-prod-db \
  --target-id redshift-prod-db \
  --mode clone \
  --suffix "-redshift"
```

**Output:**
```
================================================================================
Dataset Migration: aurora-prod-db → redshift-prod-db
Mode: CLONE
================================================================================

📦 Found 5 dataset(s) to migrate:

Processing: Sales Data (ID: sales-dataset)
  ✓ Updated table 'sales_table' to use new data source
  ✅ Successfully cloned dataset as sales-dataset-redshift

Processing: Customer Data (ID: customer-dataset)
  ✓ Updated table 'customer_table' to use new data source
  ✅ Successfully cloned dataset as customer-dataset-redshift

Processing: Product Data (ID: product-dataset)
  ✓ Updated table 'product_table' to use new data source
  ✅ Successfully cloned dataset as product-dataset-redshift

Processing: Marketing Data (ID: marketing-dataset)
  ✓ Updated table 'marketing_table' to use new data source
  ✅ Successfully cloned dataset as marketing-dataset-redshift

Processing: Finance Data (ID: finance-dataset)
  ✓ Updated table 'finance_table' to use new data source
  ✅ Successfully cloned dataset as finance-dataset-redshift

================================================================================
Migration Complete:
  ✅ Successful: 5
  ❌ Failed: 0
================================================================================
```

---

## Step 6: Test Dataset Refreshes

### Manually Refresh One Dataset in QuickSight Console

1. Go to QuickSight console
2. Navigate to Datasets
3. Open `sales-dataset-redshift`
4. Click "Refresh now"
5. Verify refresh completes successfully

✅ **Result:** Refresh completed in 12 seconds (vs 18 seconds with Aurora)

---

## Step 7: Create Dataset Mapping for Analyses

```bash
cat > config/dataset_mapping.json << EOF
{
  "sales-dataset": "sales-dataset-redshift",
  "customer-dataset": "customer-dataset-redshift",
  "product-dataset": "product-dataset-redshift",
  "marketing-dataset": "marketing-dataset-redshift",
  "finance-dataset": "finance-dataset-redshift"
}
EOF
```

---

## Step 8: Clone Critical Analyses

### Clone Sales Analysis (High Priority)

```bash
python scripts/clone_and_migrate.py \
  --aws-account-id 123456789012 \
  --region us-east-1 \
  --resource-type analysis \
  --resource-id sales-analysis \
  --dataset-mapping config/dataset_mapping.json \
  --suffix "-redshift"
```

**Output:**
```
Migrating analysis: sales-analysis
  ✓ Replaced dataset reference: sales-dataset → sales-dataset-redshift
  ✅ Successfully cloned analysis as sales-analysis-redshift
```

### Clone All Other Analyses

```bash
# Regional Sales
python scripts/clone_and_migrate.py \
  --aws-account-id 123456789012 \
  --resource-type analysis \
  --resource-id regional-sales-analysis \
  --dataset-mapping config/dataset_mapping.json \
  --suffix "-redshift"

# Customer Analysis
python scripts/clone_and_migrate.py \
  --aws-account-id 123456789012 \
  --resource-type analysis \
  --resource-id customer-analysis \
  --dataset-mapping config/dataset_mapping.json \
  --suffix "-redshift"

# Continue for all analyses...
```

---

## Step 9: Create Dashboards from New Analyses

### Via QuickSight Console (Recommended)

For each cloned analysis:

1. Open the analysis (e.g., `sales-analysis-redshift`)
2. Click "Share" → "Publish dashboard"
3. Dashboard ID: `sales-dashboard-redshift`
4. Dashboard name: `Sales Dashboard (Redshift)`
5. Click "Publish dashboard"

### Result

✅ Created 8 new dashboards:
- `sales-dashboard-redshift`
- `regional-dashboard-redshift`
- `customer-dashboard-redshift`
- `product-dashboard-redshift`
- `inventory-dashboard-redshift`
- `marketing-dashboard-redshift`
- `roi-dashboard-redshift`
- `finance-dashboard-redshift`

---

## Step 10: Parallel Testing

### Test Dashboards Side-by-Side

For one week, maintain both versions:
- **Old (Aurora):** `sales-dashboard`
- **New (Redshift):** `sales-dashboard-redshift`

### Testing Checklist

- [x] All visualizations load correctly
- [x] Numbers match between old and new
- [x] Filters work as expected
- [x] Drill-downs function properly
- [x] Performance is acceptable (actually better!)
- [x] Scheduled refreshes work
- [x] Users can access new dashboards
- [x] Row-level security works (if applicable)

**Test Duration:** March 1-7, 2025  
**Testers:** Analytics team (5 people)  
**Issues Found:** 0 critical, 2 minor (resolved)

---

## Step 11: Run Comprehensive Audit

```bash
python scripts/audit_migration.py \
  --aws-account-id 123456789012 \
  --region us-east-1 \
  --redshift-datasource-id redshift-prod-db \
  --compare-datasets sales-dataset sales-dataset-redshift
```

**Output:**
```
🔍 Auditing Redshift Data Source: redshift-prod-db
--------------------------------------------------------------------------------
  ✅ Status: OK
  Name: Production Redshift Cluster
  Type: REDSHIFT
  Cluster: prod-redshift-cluster
  Database: analytics

🔍 Auditing Datasets Using Data Source: redshift-prod-db
--------------------------------------------------------------------------------
  Found 5 dataset(s):

  ✅ Sales Data - Redshift (ID: sales-dataset-redshift)
  ✅ Customer Data - Redshift (ID: customer-dataset-redshift)
  ✅ Product Data - Redshift (ID: product-dataset-redshift)
  ✅ Marketing Data - Redshift (ID: marketing-dataset-redshift)
  ✅ Finance Data - Redshift (ID: finance-dataset-redshift)

  Summary: 5/5 datasets healthy

🔍 Auditing Dependent Analyses
--------------------------------------------------------------------------------
  Found 10 analysis/analyses:

  ✅ Sales Dashboard Analysis - Redshift (ID: sales-analysis-redshift)
     Uses datasets: sales-dataset-redshift
  ✅ Regional Sales Analysis - Redshift (ID: regional-sales-analysis-redshift)
     Uses datasets: sales-dataset-redshift
  [... 8 more analyses ...]

  Summary: 10/10 analyses healthy

🔍 Comparing Datasets
--------------------------------------------------------------------------------
  Old (Aurora): sales-dataset
  New (Redshift): sales-dataset-redshift

  ✅ Physical tables match (1 tables)
  ✅ Logical tables match (1 tables)
  ✅ Column count matches (25 columns)

================================================================================
AUDIT REPORT
================================================================================

✅ All checks passed! No issues or warnings found.

================================================================================
```

---

## Step 12: Gradual User Migration

### Week 1: Analytics Team
- Share Redshift dashboards with analytics team
- Collect feedback
- Fix any issues

### Week 2: Department Heads
- Share with department heads
- Monitor usage
- Verify performance

### Week 3: All Users
- Update default dashboard links
- Send announcement email
- Provide support for questions

**Announcement Email:**
```
Subject: New and Improved QuickSight Dashboards

Hi Team,

We've migrated our QuickSight dashboards to a new, faster data source (Redshift).

New dashboards (please bookmark):
- Sales Dashboard: https://quicksight.aws.amazon.com/...sales-dashboard-redshift
- Customer Dashboard: https://quicksight.aws.amazon.com/...customer-dashboard-redshift
[... continue for all dashboards ...]

Benefits:
- 30% faster load times
- More reliable refreshes
- Better performance for complex queries

The old dashboards will remain available for 2 more weeks for reference.

Questions? Contact analytics-team@acme.com

Thanks!
Analytics Team
```

---

## Step 13: Update Embedded Dashboards (If Applicable)

If you have embedded dashboards in applications:

```javascript
// OLD URL
const oldDashboardUrl = 'https://quicksight.aws.amazon.com/.../sales-dashboard';

// NEW URL
const newDashboardUrl = 'https://quicksight.aws.amazon.com/.../sales-dashboard-redshift';

// Update your application code
embedDashboard(newDashboardUrl);
```

Deploy updated application code during maintenance window.

---

## Step 14: Monitoring Period

### Monitor for 2 Weeks

**Metrics to Track:**
- Dashboard load times: ✅ 30% improvement
- Dataset refresh success rate: ✅ 100% (was 98%)
- User feedback: ✅ Positive
- Error rates: ✅ Zero new errors
- Query performance: ✅ Improved

**Monitoring Tools:**
- QuickSight console (refresh history)
- CloudWatch metrics
- User feedback form
- Support tickets (0 related to migration!)

---

## Step 15: Decommission Old Resources

After 2 weeks of successful operation:

### Backup Old Resources

```bash
python scripts/list_resources.py \
  --aws-account-id 123456789012 \
  --export inventory_pre_decommission.json
```

### Delete Old Dashboards (via QuickSight Console)

1. Navigate to Dashboards
2. Select old dashboards (Aurora-based)
3. Delete one by one (after confirming not in use)

### Archive Old Analyses

Instead of deleting analyses, just remove sharing:
1. Open analysis
2. Remove all user access except yourself
3. Rename with "(ARCHIVED)" suffix

### Keep Old Datasets (For Now)

Keep Aurora datasets for 1 more month as backup:
- Datasets are cheap to maintain
- Easy rollback if needed
- Delete after 1 month if no issues

---

## Step 16: Update Documentation

### Update Internal Wiki

```markdown
# QuickSight Data Sources

## Current Setup (As of March 2025)

**Primary Data Source:** Amazon Redshift
- Cluster: prod-redshift-cluster
- Database: analytics
- QuickSight Data Source ID: redshift-prod-db

**Datasets:**
- Sales Data (sales-dataset-redshift)
- Customer Data (customer-dataset-redshift)
- Product Data (product-dataset-redshift)
- Marketing Data (marketing-dataset-redshift)
- Finance Data (finance-dataset-redshift)

**Refresh Schedule:**
- Sales: Daily at 6 AM
- Customer: Daily at 7 AM
- Product: Daily at 8 AM
- Marketing: Daily at 9 AM
- Finance: Weekly on Monday at 6 AM

**Migration Completed:** March 15, 2025
```

---

## Step 17: Post-Migration Optimization

### Optimize Redshift Performance

```sql
-- Run on Redshift after 1 week of usage
ANALYZE;
VACUUM;

-- Add sort keys for commonly filtered columns
ALTER TABLE sales_table ALTER SORTKEY (sale_date, region);
ALTER TABLE customer_table ALTER SORTKEY (customer_id);

-- Check query performance
SELECT query, total_exec_time, avg_exec_time
FROM svl_query_metrics
WHERE query_id IN (
  SELECT query FROM stl_query WHERE querytxt LIKE '%quicksight%'
)
ORDER BY total_exec_time DESC
LIMIT 10;
```

### Optimize QuickSight

1. **Enable SPICE** for frequently accessed datasets
   - Sales Data: ✅ SPICE enabled (2GB)
   - Product Data: ✅ SPICE enabled (500MB)

2. **Adjust Refresh Schedules**
   - Stagger refreshes to avoid contention
   - Use incremental refresh where possible

3. **Query Result Caching**
   - Enable in QuickSight settings
   - Cache duration: 1 hour for most dashboards

---

## Final Results

### Success Metrics

| Metric | Before (Aurora) | After (Redshift) | Improvement |
|--------|----------------|------------------|-------------|
| Dashboard Load Time | 4.2 sec | 2.9 sec | 31% faster |
| Dataset Refresh Time | 18 sec | 12 sec | 33% faster |
| Refresh Success Rate | 98% | 100% | +2% |
| User Satisfaction | 7.5/10 | 8.9/10 | +19% |
| Monthly Cost | $850 | $720 | 15% savings |

### Lessons Learned

✅ **What Went Well:**
- Clone strategy allowed safe testing
- Parallel operation reduced risk
- No disruption to business users
- Performance improvements exceeded expectations

⚠️ **Challenges:**
- Initial Redshift VPC configuration took time
- Some custom SQL needed minor adjustments
- User training and communication important

💡 **Recommendations:**
- Always test in non-production first
- Budget 2-3 weeks for complete migration
- Over-communicate with stakeholders
- Monitor closely for first month

---

## Timeline Summary

| Phase | Duration | Activities |
|-------|----------|------------|
| Planning | 2 days | Assessment, schema validation, configuration |
| Data Source Setup | 1 day | Create Redshift data source, test connection |
| Dataset Migration | 1 day | Clone datasets, test refreshes |
| Analysis Migration | 2 days | Clone analyses, create dashboards |
| Testing | 1 week | Parallel testing, validation |
| User Migration | 2 weeks | Gradual rollout to all users |
| Monitoring | 2 weeks | Track metrics, gather feedback |
| Cleanup | 1 day | Decommission old resources |
| **Total** | **~5 weeks** | From start to full production |

---

## Conclusion

The migration from Aurora to Redshift was completed successfully using the clone strategy. All 5 datasets, 10 analyses, and 8 dashboards were migrated without any business disruption. Performance improved significantly, and users are satisfied with the results.

**Key Takeaway:** The QuickSight API's ability to update datasets without recreating analyses and dashboards made this migration straightforward and low-risk.
