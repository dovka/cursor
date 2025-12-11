# QuickSight Aurora to Redshift Migration Guide

This guide provides step-by-step instructions for migrating your QuickSight reports, analyses, and dashboards from Aurora PostgreSQL to Amazon Redshift.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Migration Planning](#pre-migration-planning)
3. [Migration Strategies](#migration-strategies)
4. [Step-by-Step Migration](#step-by-step-migration)
5. [Post-Migration Validation](#post-migration-validation)
6. [Rollback Plan](#rollback-plan)
7. [Common Issues](#common-issues)

---

## Prerequisites

### 1. AWS Access and Permissions

Ensure you have:
- AWS CLI configured with appropriate credentials
- QuickSight access with permissions to create/modify data sources, datasets, analyses, and dashboards
- IAM role with QuickSight API permissions (see README.md for required permissions)

### 2. Redshift Cluster Setup

Ensure your Redshift cluster:
- Is provisioned and accessible
- Has identical schema (views/tables) as Aurora with same column names and types
- Has network connectivity configured (VPC, security groups)
- Has a database user for QuickSight with appropriate permissions

### 3. Schema Validation

**Critical**: Before migration, verify that your Redshift schema matches Aurora:

```sql
-- On Aurora
SELECT table_schema, table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_schema = 'your_schema'
ORDER BY table_name, ordinal_position;

-- On Redshift (should match Aurora output)
SELECT table_schema, table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_schema = 'your_schema'
ORDER BY table_name, ordinal_position;
```

### 4. Python Environment

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

---

## Pre-Migration Planning

### Step 1: Inventory Current Resources

List all Aurora-based QuickSight resources:

```bash
python scripts/list_resources.py \
  --aws-account-id YOUR_ACCOUNT_ID \
  --region us-east-1 \
  --export inventory.json
```

This will output:
- All Aurora data sources
- Datasets using Aurora data sources
- Analyses using those datasets
- Dashboards using those analyses

**Review the output carefully** to understand dependencies.

### Step 2: Create Migration Plan

Based on the inventory, document:

1. **Data Sources to Migrate**
   - Source Aurora data source IDs
   - Target Redshift connection details

2. **Datasets Impact**
   - Number of datasets per data source
   - Dataset refresh schedules
   - Row-level security (RLS) rules

3. **Analyses and Dashboards**
   - Number of analyses per dataset
   - Number of dashboards per analysis
   - Shared analyses/dashboards and their users

4. **Migration Window**
   - Choose a low-traffic time
   - Plan for testing and validation
   - Prepare rollback procedure

### Step 3: Test Environment First

**Always test in a non-production QuickSight account first!**

If you don't have a test account:
1. Export dashboard/analysis templates
2. Import to test account
3. Perform migration test
4. Validate results
5. Document any issues

---

## Migration Strategies

### Strategy A: In-Place Update (Fast, Higher Risk)

**Best for:**
- Urgent migrations
- Environments where testing was done separately
- When you have good backups

**Process:**
1. Create Redshift data source
2. Update existing datasets to use Redshift
3. All analyses/dashboards automatically use new source

**Pros:**
- Fastest approach
- No need to update analyses/dashboards
- Minimal changes to shared resources

**Cons:**
- Cannot easily rollback
- If something breaks, everything breaks
- Limited testing in production

### Strategy B: Clone and Migrate (Safe, Gradual)

**Best for:**
- Production environments
- Critical dashboards
- When you need parallel testing

**Process:**
1. Create Redshift data source
2. Clone datasets with Redshift connection
3. Clone analyses referencing new datasets
4. Test cloned resources thoroughly
5. Gradually switch users to new resources
6. Decommission old resources after validation

**Pros:**
- Safe rollback (keep old resources)
- Parallel testing
- Gradual user migration
- Easy to compare old vs new

**Cons:**
- More time consuming
- Temporary duplication of resources
- Need to update sharing/permissions
- May need to update embedded URLs

### Strategy C: Hybrid Approach (Recommended)

**Best for:**
- Most production scenarios
- Mixed criticality dashboards

**Process:**
1. Use Strategy B (clone) for critical/complex dashboards
2. Use Strategy A (update) for simple/non-critical dashboards
3. Migrate in phases by business unit or dashboard type

---

## Step-by-Step Migration

### Phase 1: Create Redshift Data Source

1. **Configure Redshift connection details:**

```bash
# Copy example config
cp config/redshift_config.example.json config/redshift_config.json

# Edit with your Redshift details
nano config/redshift_config.json
```

2. **Create the data source:**

```bash
python scripts/create_redshift_datasource.py \
  --aws-account-id YOUR_ACCOUNT_ID \
  --region us-east-1 \
  --config config/redshift_config.json \
  --test
```

3. **Verify connection:**

Check QuickSight console or use:

```bash
python scripts/audit_migration.py \
  --aws-account-id YOUR_ACCOUNT_ID \
  --region us-east-1 \
  --redshift-datasource-id redshift-prod-datasource
```

### Phase 2: Migrate Datasets

#### Option A: In-Place Update

```bash
python scripts/migrate_datasets.py \
  --aws-account-id YOUR_ACCOUNT_ID \
  --region us-east-1 \
  --source-id aurora-datasource-id \
  --target-id redshift-prod-datasource \
  --mode update
```

**⚠️ This will modify datasets in place!**

#### Option B: Clone Datasets

```bash
python scripts/migrate_datasets.py \
  --aws-account-id YOUR_ACCOUNT_ID \
  --region us-east-1 \
  --source-id aurora-datasource-id \
  --target-id redshift-prod-datasource \
  --mode clone \
  --suffix "-redshift"
```

This creates new datasets with "-redshift" suffix.

#### Option C: Selective Migration

To migrate specific datasets only:

```bash
python scripts/migrate_datasets.py \
  --aws-account-id YOUR_ACCOUNT_ID \
  --region us-east-1 \
  --source-id aurora-datasource-id \
  --target-id redshift-prod-datasource \
  --mode clone \
  --dataset-ids dataset-1 dataset-2 dataset-3
```

### Phase 3: Migrate Analyses (Clone Mode Only)

If you cloned datasets, you need to create new analyses:

1. **Create dataset mapping file:**

```json
{
  "old-dataset-1": "old-dataset-1-redshift",
  "old-dataset-2": "old-dataset-2-redshift"
}
```

2. **Clone each analysis:**

```bash
python scripts/clone_and_migrate.py \
  --aws-account-id YOUR_ACCOUNT_ID \
  --region us-east-1 \
  --resource-type analysis \
  --resource-id your-analysis-id \
  --dataset-mapping config/dataset_mapping.json \
  --suffix "-redshift"
```

3. **Repeat for each analysis** you need to migrate.

### Phase 4: Update Dashboards

Dashboards are published from analyses. Two options:

#### Option A: Publish from New Analysis (Recommended)

1. Open the new (cloned) analysis in QuickSight console
2. Click "Share" → "Publish dashboard"
3. Give it a new name (e.g., "Dashboard Name - Redshift")
4. Set appropriate permissions

#### Option B: Update Existing Dashboard

1. Open the existing dashboard in QuickSight console
2. Click "Edit"
3. In the analysis editor, update data source references
4. Publish changes

### Phase 5: Update Schedules and Permissions

1. **Update refresh schedules:**
   - Redshift datasets may have different performance characteristics
   - Adjust refresh schedules in QuickSight console
   - Consider Redshift maintenance windows

2. **Update permissions:**
   ```bash
   # List current permissions
   aws quicksight describe-data-set-permissions \
     --aws-account-id YOUR_ACCOUNT_ID \
     --data-set-id new-dataset-id
   
   # Apply same permissions to new resources as needed
   ```

3. **Update Row-Level Security (RLS):**
   - RLS rules need to be recreated for new datasets
   - Export RLS from old dataset
   - Apply to new dataset via QuickSight console or API

---

## Post-Migration Validation

### Step 1: Audit All Resources

```bash
python scripts/audit_migration.py \
  --aws-account-id YOUR_ACCOUNT_ID \
  --region us-east-1 \
  --redshift-datasource-id redshift-prod-datasource
```

### Step 2: Compare Dataset Schemas

If you cloned datasets, compare old vs new:

```bash
python scripts/audit_migration.py \
  --aws-account-id YOUR_ACCOUNT_ID \
  --region us-east-1 \
  --redshift-datasource-id redshift-prod-datasource \
  --compare-datasets old-dataset-id new-dataset-id
```

### Step 3: Validate Data Accuracy

1. **Spot check key metrics:**
   - Open dashboards
   - Verify numbers match expectations
   - Compare with Aurora-based dashboards (if still available)

2. **Run test queries:**
   ```sql
   -- Compare row counts
   SELECT COUNT(*) FROM your_table; -- On both Aurora and Redshift
   
   -- Compare aggregations
   SELECT metric, SUM(value) FROM your_table GROUP BY metric;
   ```

3. **Check for errors:**
   - Review QuickSight console for any error messages
   - Check dataset refresh logs
   - Verify all visualizations load correctly

### Step 4: Performance Testing

1. **Dashboard load times:**
   - Time how long dashboards take to load
   - Compare with Aurora performance
   - Optimize Redshift queries if needed (SORTKEY, DISTKEY, etc.)

2. **Dataset refresh times:**
   - Monitor first few scheduled refreshes
   - Adjust schedules if needed

### Step 5: User Acceptance Testing

1. **Notify key users** about the migration
2. **Collect feedback** on any issues
3. **Address problems** before full rollout

---

## Rollback Plan

### If Using Clone Strategy

**Easy rollback:**
1. Direct users back to original dashboards/analyses
2. Fix issues with new resources
3. Retry migration when ready
4. Keep both versions until confident

### If Using Update Strategy

**More complex rollback:**

1. **Immediate rollback:**
   ```bash
   # Update datasets back to Aurora
   python scripts/migrate_datasets.py \
     --aws-account-id YOUR_ACCOUNT_ID \
     --source-id redshift-prod-datasource \
     --target-id aurora-datasource-id \
     --mode update
   ```

2. **From backup (if you exported before migration):**
   - Delete modified resources
   - Re-import from saved definitions
   - Recreate datasets manually if needed

### Prevention

**Before any in-place migration:**

1. **Export resources:**
   ```bash
   python scripts/list_resources.py \
     --aws-account-id YOUR_ACCOUNT_ID \
     --export backup-$(date +%Y%m%d).json
   ```

2. **Document current state:**
   - Screenshot critical dashboards
   - Export dataset definitions
   - Note all custom SQL queries

---

## Common Issues

### Issue 1: Data Source Connection Failed

**Symptoms:** Cannot create or connect to Redshift data source

**Solutions:**
1. Verify security group allows QuickSight IPs
2. Check VPC connection configuration
3. Verify database credentials
4. Ensure Redshift cluster is publicly accessible (if not using VPC connection)
5. Check Redshift cluster status

```bash
# Get QuickSight IP ranges for your region
aws ec2 describe-managed-prefix-lists \
  --filters Name=prefix-list-name,Values="com.amazonaws.${AWS_REGION}.quicksight" \
  --query 'PrefixLists[*].PrefixListId'
```

### Issue 2: Schema Mismatch Errors

**Symptoms:** Dataset refresh fails, "Column not found" errors

**Solutions:**
1. Verify Redshift schema exactly matches Aurora
2. Check for case sensitivity differences
3. Ensure data types are compatible
4. Review custom SQL in datasets

```sql
-- Check for case differences
SELECT LOWER(column_name) as col, COUNT(*) 
FROM information_schema.columns 
WHERE table_schema = 'your_schema'
GROUP BY LOWER(column_name) 
HAVING COUNT(*) > 1;
```

### Issue 3: Permission Denied

**Symptoms:** "You don't have permission to access this resource"

**Solutions:**
1. Grant QuickSight role access to Redshift
2. Update IAM policies
3. Check database user permissions
4. Verify VPC connection permissions

```sql
-- Grant permissions to QuickSight user in Redshift
GRANT SELECT ON ALL TABLES IN SCHEMA your_schema TO quicksight_user;
GRANT USAGE ON SCHEMA your_schema TO quicksight_user;
```

### Issue 4: Performance Degradation

**Symptoms:** Dashboards load slowly, timeouts

**Solutions:**
1. Optimize Redshift tables (VACUUM, ANALYZE)
2. Add sort and distribution keys
3. Review and optimize queries
4. Consider materialized views
5. Adjust WLM (Workload Management) queues

```sql
-- Analyze table statistics
ANALYZE your_table;

-- Add sort key for commonly filtered columns
ALTER TABLE your_table ALTER SORTKEY (date_column, id_column);
```

### Issue 5: Row-Level Security Not Working

**Symptoms:** Users see wrong data or all data

**Solutions:**
1. Recreate RLS rules for new datasets
2. Verify RLS dataset is also migrated
3. Check user mappings in RLS
4. Test with different user roles

### Issue 6: Embedded Dashboards Not Working

**Symptoms:** Embedded dashboards show errors or wrong data

**Solutions:**
1. Update embed URLs if using new (cloned) dashboards
2. Regenerate embed codes
3. Update dashboard IDs in embedding application
4. Refresh dashboard permissions

### Issue 7: Scheduled Refresh Failures

**Symptoms:** Dataset refreshes fail on schedule

**Solutions:**
1. Check Redshift cluster maintenance schedule
2. Verify QuickSight VPC connection timeout settings
3. Optimize long-running queries
4. Review Redshift WLM queue configuration
5. Check for concurrent refresh limits

---

## Best Practices

### 1. Communication

- **Notify stakeholders** before migration
- **Set expectations** for downtime (if any)
- **Provide timeline** with milestones
- **Designate points of contact** for issues

### 2. Testing

- **Test in non-production first**
- **Validate data accuracy** thoroughly
- **Performance test** under load
- **User acceptance testing** with real users

### 3. Phased Rollout

- **Start with non-critical dashboards**
- **Migrate in waves** by business unit
- **Monitor each phase** before proceeding
- **Keep old resources** until fully validated

### 4. Documentation

- **Document the process** as you go
- **Record any issues** and solutions
- **Update runbooks** for future migrations
- **Create user guides** if needed

### 5. Monitoring

- **Set up alerts** for refresh failures
- **Monitor Redshift performance**
- **Track dashboard usage** before and after
- **Review user feedback** regularly

### 6. Optimization

After migration:
- **Review query performance** in Redshift
- **Optimize slow queries**
- **Add appropriate indexes** (sort/dist keys)
- **Consider query caching** in QuickSight
- **Use SPICE** where appropriate

---

## Support and Resources

- [AWS QuickSight Documentation](https://docs.aws.amazon.com/quicksight/)
- [Amazon Redshift Best Practices](https://docs.aws.amazon.com/redshift/latest/dg/best-practices.html)
- [QuickSight API Reference](https://docs.aws.amazon.com/quicksight/latest/APIReference/)
- [QuickSight Community Forums](https://repost.aws/tags/TA4ckwIlTgSRKG43KLBs97ug/amazon-quick-sight)

---

## Appendix: API Reference

### Key QuickSight API Operations Used

- `CreateDataSource` - Create Redshift data source
- `UpdateDataSource` - Modify data source connection
- `DescribeDataSource` - Get data source details
- `CreateDataSet` - Clone dataset
- `UpdateDataSet` - Modify dataset data source
- `DescribeDataSet` - Get dataset definition
- `CreateAnalysis` - Clone analysis
- `UpdateAnalysis` - Modify analysis
- `DescribeAnalysisDefinition` - Get analysis definition
- `CreateDashboard` - Publish dashboard
- `DescribeDashboardDefinition` - Get dashboard definition

### Rate Limits

QuickSight API has rate limits. The scripts include rate limiting, but for large migrations:
- Batch operations when possible
- Add delays between API calls
- Monitor for throttling errors
- Use exponential backoff

---

**Questions or Issues?**

If you encounter issues not covered in this guide, check:
1. AWS CloudTrail logs for API errors
2. Redshift query logs for database errors
3. QuickSight console for error messages
4. This repository's issue tracker

Good luck with your migration!
