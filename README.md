# QuickSight Migration: Aurora to Redshift

This repository contains tools and documentation for migrating AWS QuickSight reports, analyses, and dashboards from Aurora PostgreSQL data sources to Amazon Redshift.

## TL;DR - Quick Answer

**Question:** Can you modify QuickSight reports/analyses/dashboards to use Redshift instead of Aurora without recreating them?

**Answer:** **YES!** You can do this via the QuickSight API in several ways:

1. **Best Approach:** Update the data source connection in your **datasets** to point to Redshift instead of Aurora. Since analyses and dashboards reference datasets (not data sources directly), they automatically use the new Redshift connection. No need to modify analyses or dashboards at all!

2. **Safer Approach:** Clone datasets with Redshift connections, then clone analyses/dashboards to reference the new datasets. This allows parallel testing before switching users.

3. **API Support:** All of this is fully supported via AWS QuickSight API using operations like `UpdateDataSet`, `CreateDataSet`, `CreateAnalysis`, etc.

**The key insight:** You don't need to recreate analyses and dashboards if you update the underlying datasets. The data source swap happens at the dataset level.

---

## Overview

**Can you migrate without recreating from scratch?**

**Absolutely!** AWS QuickSight API provides several approaches to migrate from Aurora to Redshift:

### Option 1: Update Existing DataSets (Recommended)
- Modify the data source connection in existing datasets
- All dashboards and analyses using these datasets automatically point to the new source
- **Pros**: No need to modify dashboards/analyses themselves
- **Cons**: Direct in-place modification (test carefully)

### Option 2: Clone and Replace Strategy
- Clone dashboards/analyses with new names
- Update their dataset references to point to Redshift-backed datasets
- Test thoroughly, then replace originals
- **Pros**: Safer, allows parallel testing
- **Cons**: More steps, temporary duplication

### Option 3: Create New DataSets with Same Schema
- Create new datasets with identical schemas pointing to Redshift
- Update analyses and dashboards to use new datasets
- **Pros**: Clean separation, easy rollback
- **Cons**: Requires mapping and updating references

## Architecture

```
Aurora DataSource → DataSet → Analysis → Dashboard
                      ↓ (Update)
Redshift DataSource → DataSet → Analysis → Dashboard
```

## Prerequisites

- Python 3.7+
- AWS credentials configured with QuickSight permissions
- boto3 library
- QuickSight Enterprise Edition (for some API features)

## Required IAM Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "quicksight:DescribeDataSource",
        "quicksight:CreateDataSource",
        "quicksight:UpdateDataSource",
        "quicksight:DescribeDataSet",
        "quicksight:CreateDataSet",
        "quicksight:UpdateDataSet",
        "quicksight:DescribeAnalysis",
        "quicksight:DescribeAnalysisDefinition",
        "quicksight:CreateAnalysis",
        "quicksight:UpdateAnalysis",
        "quicksight:DescribeDashboard",
        "quicksight:DescribeDashboardDefinition",
        "quicksight:CreateDashboard",
        "quicksight:UpdateDashboard",
        "quicksight:ListDataSources",
        "quicksight:ListDataSets",
        "quicksight:ListAnalyses",
        "quicksight:ListDashboards"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### Option A: Automated Batch Migration (Recommended)

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Configure your AWS credentials:
```bash
aws configure
```

3. Create migration configuration:
```bash
cp config/migration_config.example.json config/migration_config.json
# Edit config/migration_config.json with your details
```

4. Run batch migration:
```bash
python scripts/batch_migrate.py --config config/migration_config.json
```

That's it! The script will handle everything: creating the Redshift data source, migrating datasets, and auditing the results.

### Option B: Step-by-Step Manual Migration

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Configure your AWS credentials:
```bash
aws configure
```

3. List your current Aurora data sources:
```bash
python scripts/list_resources.py --aws-account-id YOUR_ACCOUNT_ID
```

4. Create Redshift data source:
```bash
python scripts/create_redshift_datasource.py --config config/redshift_config.json
```

5. Migrate datasets:
```bash
python scripts/migrate_datasets.py --source-id aurora-ds-id --target-id redshift-ds-id --aws-account-id YOUR_ACCOUNT_ID
```

## Scripts

| Script | Purpose |
|--------|---------|
| `list_resources.py` | List all QuickSight resources (data sources, datasets, analyses, dashboards) |
| `create_redshift_datasource.py` | Create a new Redshift data source |
| `migrate_datasets.py` | Update datasets to use Redshift instead of Aurora |
| `clone_and_migrate.py` | Clone analyses/dashboards and update their dataset references |
| `audit_migration.py` | Verify migration and check for issues |
| `batch_migrate.py` | **End-to-end automated migration** (recommended for most users) |

## Migration Strategies

### Strategy 1: In-Place Dataset Update (Fastest)

```bash
# 1. Create Redshift data source
python scripts/create_redshift_datasource.py --config config/redshift_config.json

# 2. Update datasets to point to Redshift
python scripts/migrate_datasets.py \
  --source-id aurora-source-id \
  --target-id redshift-source-id \
  --aws-account-id YOUR_ACCOUNT_ID \
  --mode update
```

### Strategy 2: Clone and Test (Safest)

```bash
# 1. Create Redshift data source
python scripts/create_redshift_datasource.py --config config/redshift_config.json

# 2. Clone datasets with Redshift connection
python scripts/migrate_datasets.py \
  --source-id aurora-source-id \
  --target-id redshift-source-id \
  --aws-account-id YOUR_ACCOUNT_ID \
  --mode clone \
  --suffix "-redshift"

# 3. Clone and update analyses
python scripts/clone_and_migrate.py \
  --resource-type analysis \
  --aws-account-id YOUR_ACCOUNT_ID \
  --suffix "-redshift"

# 4. Test thoroughly, then promote
```

## Important Considerations

1. **Schema Compatibility**: Ensure Redshift views/tables have identical column names and types as Aurora
2. **Data Type Mapping**: PostgreSQL and Redshift have subtle differences in data types
3. **Permissions**: QuickSight must have access to Redshift cluster
4. **Network**: Ensure VPC/Security group configuration allows QuickSight access
5. **Testing**: Always test in a non-production account first
6. **Backup**: Consider exporting dashboard/analysis definitions before migration

## Limitations

- Some QuickSight features may require Enterprise Edition
- Embedded dashboards may need URL updates
- Row-level security (RLS) rules need to be recreated for new datasets
- Scheduled refreshes need to be reconfigured

## Troubleshooting

### Common Issues

1. **Permission Denied**: Check IAM permissions and QuickSight service role
2. **Data Source Connection Failed**: Verify Redshift cluster accessibility and credentials
3. **Schema Mismatch**: Ensure Redshift tables match Aurora schema exactly
4. **API Throttling**: Implement exponential backoff (included in scripts)

## Additional Documentation

⭐ **[INDEX.md](INDEX.md)** - Comprehensive documentation index and navigation guide

📖 **Start Here:**
- **[GETTING_STARTED.md](GETTING_STARTED.md)** - 5-minute quick start guide

📚 **Detailed Guides:**
- **[PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)** - Executive summary and overview
- **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)** - Comprehensive step-by-step migration guide
- **[EXAMPLE_WORKFLOW.md](EXAMPLE_WORKFLOW.md)** - Complete real-world migration example

🔧 **Reference:**
- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - Command quick reference and cheat sheet
- **[API_REFERENCE.md](API_REFERENCE.md)** - Detailed QuickSight API documentation

## References

- [AWS QuickSight API Documentation](https://docs.aws.amazon.com/quicksight/latest/APIReference/)
- [QuickSight Data Source Management](https://docs.aws.amazon.com/quicksight/latest/user/working-with-data-sources.html)
- [Migrating to Redshift Best Practices](https://docs.aws.amazon.com/redshift/latest/dg/best-practices.html)

## Contributing

Found a bug or have a suggestion? Please open an issue or submit a pull request!
