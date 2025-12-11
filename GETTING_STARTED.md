# Getting Started

This is a **5-minute quick start** guide to migrate your QuickSight resources from Aurora to Redshift.

## Prerequisites Check

Before starting, ensure you have:

- [ ] AWS CLI configured (`aws configure`)
- [ ] Python 3.7+ installed (`python --version`)
- [ ] Access to both Aurora and Redshift databases
- [ ] QuickSight permissions (see [README.md](README.md) for details)
- [ ] Redshift cluster provisioned and accessible

## Installation

```bash
# Clone/download this repository
cd /path/to/quicksight-migration

# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

## Quick Migration (3 Steps)

### Step 1: Create Configuration File

```bash
# Copy example config
cp config/migration_config.example.json config/migration_config.json

# Edit with your details
nano config/migration_config.json
```

**Required fields:**
```json
{
  "aws_account_id": "123456789012",           # Your AWS account ID
  "region": "us-east-1",                      # Your AWS region
  "aurora_datasource_id": "aurora-prod",      # Your Aurora data source ID
  "redshift_config": {
    "data_source_id": "redshift-prod",        # New Redshift data source ID
    "name": "Production Redshift",
    "cluster_id": "my-cluster",               # Redshift cluster name
    "host": "cluster.region.redshift.amazonaws.com",  # Redshift endpoint
    "port": 5439,
    "database": "analytics",                  # Database name
    "username": "quicksight_user",            # Database user
    "password": "YOUR_PASSWORD"               # Database password
  },
  "migration_mode": "clone",                  # Use "clone" for safety
  "suffix": "-redshift"
}
```

### Step 2: Find Your Aurora Data Source ID

```bash
# List all QuickSight data sources
python scripts/list_resources.py --aws-account-id YOUR_ACCOUNT_ID
```

Look for your Aurora data source in the output and note its ID.

### Step 3: Run Migration

```bash
# Dry run first (validates configuration)
python scripts/batch_migrate.py --config config/migration_config.json --dry-run

# If validation passes, run actual migration
python scripts/batch_migrate.py --config config/migration_config.json
```

**That's it!** The script will:
1. ✅ Create Redshift data source
2. ✅ Test connection
3. ✅ Migrate all datasets
4. ✅ Run audit checks
5. ✅ Generate report

## What Happens Next?

### If You Used "clone" Mode (Recommended)

You now have:
- ✅ Original datasets (Aurora) - still working
- ✅ New datasets (Redshift) - ready to test
- ✅ Original analyses/dashboards - unchanged

**Next steps:**
1. Test new datasets in QuickSight console
2. Clone analyses to use new datasets (see [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md))
3. Create new dashboards from cloned analyses
4. Gradually migrate users to new dashboards
5. Decommission old resources after validation

### If You Used "update" Mode (Fast but Risky)

You now have:
- ✅ All datasets using Redshift
- ✅ All analyses automatically using Redshift
- ✅ All dashboards automatically using Redshift

**Next steps:**
1. Verify all dashboards work correctly
2. Test dataset refreshes
3. Monitor for any errors

## Verify Migration

```bash
# Run audit to check everything
python scripts/audit_migration.py \
  --aws-account-id YOUR_ACCOUNT_ID \
  --redshift-datasource-id redshift-prod
```

Look for:
- ✅ All checks passed
- ✅ No errors reported
- ✅ All datasets healthy

## Common Issues

### Issue: "Connection failed"

**Solution:** Check security groups and VPC configuration
```bash
# Verify Redshift cluster is accessible
psql -h your-cluster.redshift.amazonaws.com -U username -d database -p 5439
```

### Issue: "Permission denied"

**Solution:** Check IAM permissions and QuickSight role
```bash
# Verify your IAM permissions
aws quicksight describe-data-source \
  --aws-account-id YOUR_ACCOUNT_ID \
  --data-source-id test-datasource
```

### Issue: "Dataset refresh failed"

**Solution:** Verify schema compatibility between Aurora and Redshift
```sql
-- Run on both Aurora and Redshift to compare
SELECT table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_schema = 'public'
ORDER BY table_name, column_name;
```

## Need Help?

1. **Read the guides:**
   - [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) - Detailed instructions
   - [EXAMPLE_WORKFLOW.md](EXAMPLE_WORKFLOW.md) - Real-world example
   - [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Command reference

2. **Check the API reference:**
   - [API_REFERENCE.md](API_REFERENCE.md) - Technical details

3. **Review AWS documentation:**
   - [QuickSight API](https://docs.aws.amazon.com/quicksight/latest/APIReference/)
   - [Redshift Best Practices](https://docs.aws.amazon.com/redshift/latest/dg/best-practices.html)

## Success!

If you see this output, your migration is complete:

```
================================================================================
MIGRATION REPORT
================================================================================

Results:
  Redshift Data Source: ✅ Created
  Datasets Migrated: 5
  Datasets Failed: 0
  Audit Status: ✅ Passed

✅ Migration completed successfully!
================================================================================
```

**Congratulations!** Your QuickSight resources are now using Redshift.

---

**Next:** Read [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) for post-migration steps.
