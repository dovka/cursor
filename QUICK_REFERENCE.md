# Quick Reference Guide

## Common Commands

### 1. List All Resources
```bash
python scripts/list_resources.py \
  --aws-account-id 123456789012 \
  --export inventory.json
```

### 2. Create Redshift Data Source
```bash
python scripts/create_redshift_datasource.py \
  --aws-account-id 123456789012 \
  --config config/redshift_config.json \
  --test
```

### 3. Migrate Datasets (Clone Mode - Safe)
```bash
python scripts/migrate_datasets.py \
  --aws-account-id 123456789012 \
  --source-id aurora-ds-id \
  --target-id redshift-ds-id \
  --mode clone \
  --suffix "-redshift"
```

### 4. Migrate Datasets (Update Mode - Fast)
```bash
python scripts/migrate_datasets.py \
  --aws-account-id 123456789012 \
  --source-id aurora-ds-id \
  --target-id redshift-ds-id \
  --mode update
```

### 5. Migrate Specific Datasets Only
```bash
python scripts/migrate_datasets.py \
  --aws-account-id 123456789012 \
  --source-id aurora-ds-id \
  --target-id redshift-ds-id \
  --mode clone \
  --dataset-ids dataset-1 dataset-2 dataset-3
```

### 6. Clone Analysis
```bash
python scripts/clone_and_migrate.py \
  --aws-account-id 123456789012 \
  --resource-type analysis \
  --resource-id analysis-id \
  --dataset-mapping config/dataset_mapping.json \
  --suffix "-redshift"
```

### 7. Audit Migration
```bash
python scripts/audit_migration.py \
  --aws-account-id 123456789012 \
  --redshift-datasource-id redshift-ds-id
```

### 8. Compare Datasets
```bash
python scripts/audit_migration.py \
  --aws-account-id 123456789012 \
  --redshift-datasource-id redshift-ds-id \
  --compare-datasets old-dataset-id new-dataset-id
```

---

## Decision Tree

```
Need to migrate QuickSight from Aurora to Redshift?
│
├─ Is this a production environment?
│  │
│  ├─ YES → Use CLONE mode
│  │        ├─ Test cloned resources
│  │        ├─ Gradually switch users
│  │        └─ Decommission old resources
│  │
│  └─ NO → Can use UPDATE mode
│           └─ Faster but less safe
│
├─ Do you have a test environment?
│  │
│  ├─ YES → Test migration there first
│  │        └─ Document any issues
│  │
│  └─ NO → Must use CLONE mode
│           └─ Cannot risk breaking production
│
└─ How many resources to migrate?
   │
   ├─ < 10 datasets → Manual migration acceptable
   │                   Use provided scripts
   │
   └─ > 10 datasets → Use automation scripts
                      Consider phased migration
```

---

## Migration Checklist

### Pre-Migration
- [ ] Export current resource inventory
- [ ] Verify Redshift schema matches Aurora
- [ ] Test Redshift connection
- [ ] Create Redshift data source in QuickSight
- [ ] Backup current configurations
- [ ] Notify stakeholders
- [ ] Test in non-prod environment

### During Migration
- [ ] Migrate datasets (clone or update)
- [ ] Verify dataset refresh works
- [ ] Migrate analyses (if cloned datasets)
- [ ] Test analyses with new datasets
- [ ] Create/update dashboards
- [ ] Apply permissions
- [ ] Configure RLS (if needed)
- [ ] Set up refresh schedules

### Post-Migration
- [ ] Run audit script
- [ ] Compare dataset schemas
- [ ] Validate data accuracy
- [ ] Test dashboard performance
- [ ] User acceptance testing
- [ ] Monitor for errors
- [ ] Update documentation
- [ ] Decommission old resources (after validation)

---

## Troubleshooting Quick Fixes

### Connection Failed
```bash
# Check security group
aws ec2 describe-security-groups --group-ids sg-xxxxx

# Test Redshift connection
psql -h your-cluster.redshift.amazonaws.com -U username -d database -p 5439
```

### Dataset Refresh Failed
```sql
-- On Redshift, check if tables exist
SELECT * FROM information_schema.tables WHERE table_schema = 'your_schema';

-- Check permissions
SELECT * FROM pg_tables WHERE schemaname = 'your_schema';
```

### Schema Mismatch
```sql
-- Compare columns
-- Run on both Aurora and Redshift
SELECT table_name, column_name, data_type, ordinal_position
FROM information_schema.columns
WHERE table_schema = 'your_schema'
ORDER BY table_name, ordinal_position;
```

### Performance Issues
```sql
-- Analyze tables (run on Redshift after migration)
ANALYZE your_table;

-- Vacuum tables
VACUUM your_table;

-- Check query performance
SELECT query, total_exec_time, avg_exec_time, calls
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

---

## AWS CLI Useful Commands

### QuickSight
```bash
# List data sources
aws quicksight list-data-sources --aws-account-id 123456789012

# List datasets
aws quicksight list-data-sets --aws-account-id 123456789012

# List analyses
aws quicksight list-analyses --aws-account-id 123456789012

# List dashboards
aws quicksight list-dashboards --aws-account-id 123456789012

# Describe data source
aws quicksight describe-data-source \
  --aws-account-id 123456789012 \
  --data-source-id datasource-id
```

### Redshift
```bash
# Describe cluster
aws redshift describe-clusters --cluster-identifier my-cluster

# Get cluster endpoint
aws redshift describe-clusters \
  --cluster-identifier my-cluster \
  --query 'Clusters[0].Endpoint.Address' \
  --output text
```

---

## File Structure

```
/workspace/
├── README.md                          # Main documentation
├── MIGRATION_GUIDE.md                 # Detailed migration guide
├── QUICK_REFERENCE.md                 # This file
├── requirements.txt                   # Python dependencies
├── .gitignore                         # Git ignore rules
├── config/
│   ├── redshift_config.example.json  # Example Redshift config
│   └── dataset_mapping.example.json  # Example dataset mapping
└── scripts/
    ├── list_resources.py             # Inventory QuickSight resources
    ├── create_redshift_datasource.py # Create Redshift data source
    ├── migrate_datasets.py           # Migrate datasets
    ├── clone_and_migrate.py          # Clone analyses/dashboards
    └── audit_migration.py            # Validate migration
```

---

## Environment Variables (Optional)

Create a `.env` file for convenience:

```bash
# .env
AWS_ACCOUNT_ID=123456789012
AWS_REGION=us-east-1
AURORA_DATASOURCE_ID=aurora-prod
REDSHIFT_DATASOURCE_ID=redshift-prod
```

Then use in scripts:
```bash
source .env
python scripts/list_resources.py --aws-account-id $AWS_ACCOUNT_ID
```

---

## Key Concepts

### Data Source
- Connection to database (Aurora, Redshift, etc.)
- Contains connection parameters (host, port, database, credentials)
- Can be shared across multiple datasets

### Dataset
- References one or more data sources
- Contains physical tables (direct database tables/views)
- Contains logical tables (transformations, joins, calculated fields)
- Used by analyses

### Analysis
- Interactive workspace for creating visualizations
- References one or more datasets
- Can be shared with other users
- Used as source for dashboards

### Dashboard
- Published version of an analysis
- Read-only for consumers
- Can be embedded in applications
- Supports scheduling and subscriptions

---

## Migration Patterns

### Pattern 1: Direct Update
```
Aurora DataSource → Dataset → Analysis → Dashboard
         ↓ (update)
Redshift DataSource → Dataset → Analysis → Dashboard
```
**Use when:** Low risk tolerance acceptable, have good backups

### Pattern 2: Clone Everything
```
Aurora DS → Dataset → Analysis → Dashboard (original)
Redshift DS → Dataset (clone) → Analysis (clone) → Dashboard (clone)
```
**Use when:** Need parallel testing, production environment

### Pattern 3: Hybrid
```
Critical: Use Pattern 2 (clone)
Non-Critical: Use Pattern 1 (update)
```
**Use when:** Mixed criticality, want to optimize time/safety

---

## Performance Tips

### For Redshift
1. Use sort keys on frequently filtered columns
2. Use distribution keys for large tables
3. Run VACUUM and ANALYZE regularly
4. Optimize WLM queues for QuickSight
5. Consider materialized views for complex queries

### For QuickSight
1. Use SPICE for faster query performance
2. Enable query result caching
3. Optimize dataset refresh schedules
4. Use incremental refresh where possible
5. Consider pre-aggregated datasets

---

## Security Checklist

- [ ] Use VPC connection for private Redshift access
- [ ] Enable SSL/TLS for data in transit
- [ ] Use IAM authentication when possible
- [ ] Implement row-level security (RLS) as needed
- [ ] Follow least privilege principle for database users
- [ ] Rotate credentials regularly
- [ ] Enable CloudTrail logging
- [ ] Review QuickSight permissions regularly
- [ ] Use private subnets for Redshift
- [ ] Enable Redshift encryption at rest

---

## Cost Optimization

### QuickSight
- Clean up unused analyses and dashboards
- Remove duplicate datasets
- Optimize SPICE capacity usage
- Review user licensing (Reader vs Author)

### Redshift
- Right-size cluster based on actual usage
- Use Reserved Instances for predictable workloads
- Enable automatic pause/resume for dev clusters
- Optimize queries to reduce compute time
- Use Redshift Spectrum for infrequently accessed data

---

## Support Resources

- **AWS Support**: For QuickSight/Redshift technical issues
- **AWS Forums**: Community support
- **This Repository**: Scripts and documentation updates
- **AWS Documentation**: Detailed API references

**Pro Tips:**
- Always test in non-production first
- Keep backups before major changes
- Monitor for 24-48 hours post-migration
- Document everything for future reference
- Communicate with stakeholders throughout
