# QuickSight API Reference for Migration

This document provides detailed information about the AWS QuickSight API operations used in this migration toolkit.

## Core Concepts

### Resource Hierarchy

```
Data Source (Aurora/Redshift)
    ↓ (referenced by)
Dataset
    ↓ (referenced by)
Analysis
    ↓ (published as)
Dashboard
```

**Key Insight:** Analyses and dashboards reference **datasets**, not data sources directly. This means you can change the data source at the dataset level without modifying analyses or dashboards.

---

## Data Source Operations

### CreateDataSource

Creates a new data source connection.

**API Call:**
```python
response = client.create_data_source(
    AwsAccountId='string',
    DataSourceId='string',
    Name='string',
    Type='REDSHIFT',  # or 'AURORA_POSTGRESQL', 'POSTGRESQL', etc.
    DataSourceParameters={
        'RedshiftParameters': {
            'Host': 'string',
            'Port': 123,
            'Database': 'string',
            'ClusterId': 'string'
        }
    },
    Credentials={
        'CredentialPair': {
            'Username': 'string',
            'Password': 'string'
        }
    },
    VpcConnectionProperties={
        'VpcConnectionArn': 'string'
    },
    Permissions=[
        {
            'Principal': 'arn:aws:quicksight:region:account:user/namespace/username',
            'Actions': [
                'quicksight:DescribeDataSource',
                'quicksight:PassDataSource',
                'quicksight:UpdateDataSource'
            ]
        }
    ]
)
```

**Response:**
```python
{
    'Arn': 'arn:aws:quicksight:region:account:datasource/datasource-id',
    'DataSourceId': 'string',
    'CreationStatus': 'CREATION_IN_PROGRESS',
    'Status': 200
}
```

**Used in:** `create_redshift_datasource.py`

---

### DescribeDataSource

Retrieves information about a data source.

**API Call:**
```python
response = client.describe_data_source(
    AwsAccountId='string',
    DataSourceId='string'
)
```

**Response:**
```python
{
    'DataSource': {
        'Arn': 'string',
        'DataSourceId': 'string',
        'Name': 'string',
        'Type': 'REDSHIFT',
        'Status': 'CREATION_SUCCESSFUL',  # or 'CREATION_FAILED'
        'CreatedTime': datetime(2025, 1, 1),
        'LastUpdatedTime': datetime(2025, 1, 1),
        'DataSourceParameters': {
            'RedshiftParameters': {
                'Host': 'string',
                'Port': 123,
                'Database': 'string',
                'ClusterId': 'string'
            }
        },
        'VpcConnectionProperties': {
            'VpcConnectionArn': 'string'
        }
    },
    'Status': 200
}
```

**Used in:** `list_resources.py`, `create_redshift_datasource.py`, `audit_migration.py`

---

### UpdateDataSource

Updates an existing data source.

**API Call:**
```python
response = client.update_data_source(
    AwsAccountId='string',
    DataSourceId='string',
    Name='string',
    DataSourceParameters={
        'RedshiftParameters': {
            'Host': 'string',
            'Port': 123,
            'Database': 'string',
            'ClusterId': 'string'
        }
    },
    Credentials={
        'CredentialPair': {
            'Username': 'string',
            'Password': 'string'
        }
    }
)
```

**Used in:** `create_redshift_datasource.py`

---

### ListDataSources

Lists all data sources in an account.

**API Call:**
```python
response = client.list_data_sources(
    AwsAccountId='string',
    NextToken='string',
    MaxResults=123
)
```

**Response:**
```python
{
    'DataSources': [
        {
            'Arn': 'string',
            'DataSourceId': 'string',
            'Name': 'string',
            'Type': 'AURORA_POSTGRESQL',
            'CreatedTime': datetime(2025, 1, 1),
            'LastUpdatedTime': datetime(2025, 1, 1)
        }
    ],
    'NextToken': 'string',
    'Status': 200
}
```

**Used in:** `list_resources.py`

---

## Dataset Operations

### CreateDataSet

Creates a new dataset.

**API Call:**
```python
response = client.create_data_set(
    AwsAccountId='string',
    DataSetId='string',
    Name='string',
    PhysicalTableMap={
        'table-id': {
            'RelationalTable': {
                'DataSourceArn': 'arn:aws:quicksight:region:account:datasource/datasource-id',
                'Schema': 'public',
                'Name': 'table_name',
                'InputColumns': [
                    {
                        'Name': 'column_name',
                        'Type': 'STRING'  # or INTEGER, DECIMAL, DATETIME
                    }
                ]
            }
        }
    },
    LogicalTableMap={
        'logical-table-id': {
            'Alias': 'display_name',
            'Source': {
                'PhysicalTableId': 'table-id'
            },
            'DataTransforms': [
                {
                    'ProjectOperation': {
                        'ProjectedColumns': ['column1', 'column2']
                    }
                }
            ]
        }
    },
    ImportMode='DIRECT_QUERY',  # or 'SPICE'
    Permissions=[
        {
            'Principal': 'arn:aws:quicksight:region:account:user/namespace/username',
            'Actions': [
                'quicksight:DescribeDataSet',
                'quicksight:PassDataSet',
                'quicksight:UpdateDataSet'
            ]
        }
    ]
)
```

**Response:**
```python
{
    'Arn': 'arn:aws:quicksight:region:account:dataset/dataset-id',
    'DataSetId': 'string',
    'IngestionArn': 'string',
    'IngestionId': 'string',
    'Status': 200
}
```

**Used in:** `migrate_datasets.py` (clone mode)

---

### UpdateDataSet

Updates an existing dataset.

**API Call:**
```python
response = client.update_data_set(
    AwsAccountId='string',
    DataSetId='string',
    Name='string',
    PhysicalTableMap={
        'table-id': {
            'RelationalTable': {
                'DataSourceArn': 'NEW_REDSHIFT_DATASOURCE_ARN',  # Changed!
                'Schema': 'public',
                'Name': 'table_name',
                'InputColumns': [...]
            }
        }
    },
    LogicalTableMap={...},
    ImportMode='DIRECT_QUERY'
)
```

**This is the key operation for in-place migration!**

**Used in:** `migrate_datasets.py` (update mode)

---

### DescribeDataSet

Retrieves dataset information.

**API Call:**
```python
response = client.describe_data_set(
    AwsAccountId='string',
    DataSetId='string'
)
```

**Response:**
```python
{
    'DataSet': {
        'Arn': 'string',
        'DataSetId': 'string',
        'Name': 'string',
        'CreatedTime': datetime(2025, 1, 1),
        'LastUpdatedTime': datetime(2025, 1, 1),
        'PhysicalTableMap': {...},
        'LogicalTableMap': {...},
        'OutputColumns': [
            {
                'Name': 'column_name',
                'Type': 'STRING'
            }
        ],
        'ImportMode': 'DIRECT_QUERY',
        'RowLevelPermissionDataSet': {
            'Arn': 'string',
            'PermissionPolicy': 'GRANT_ACCESS'
        }
    },
    'Status': 200
}
```

**Used in:** All migration scripts

---

### ListDataSets

Lists all datasets.

**API Call:**
```python
response = client.list_data_sets(
    AwsAccountId='string',
    NextToken='string',
    MaxResults=123
)
```

**Used in:** `list_resources.py`, `migrate_datasets.py`

---

## Analysis Operations

### CreateAnalysis

Creates a new analysis.

**API Call:**
```python
response = client.create_analysis(
    AwsAccountId='string',
    AnalysisId='string',
    Name='string',
    Definition={
        'DataSetIdentifierDeclarations': [
            {
                'Identifier': 'dataset1',
                'DataSetArn': 'arn:aws:quicksight:region:account:dataset/dataset-id'
            }
        ],
        'Sheets': [
            {
                'SheetId': 'sheet-id',
                'Name': 'Sheet Name',
                'Visuals': [...]
            }
        ]
    },
    Permissions=[...]
)
```

**Used in:** `clone_and_migrate.py`

---

### DescribeAnalysis

Retrieves analysis metadata.

**API Call:**
```python
response = client.describe_analysis(
    AwsAccountId='string',
    AnalysisId='string'
)
```

**Response:**
```python
{
    'Analysis': {
        'AnalysisId': 'string',
        'Arn': 'string',
        'Name': 'string',
        'Status': 'CREATION_SUCCESSFUL',
        'CreatedTime': datetime(2025, 1, 1),
        'LastUpdatedTime': datetime(2025, 1, 1),
        'DataSetArns': [
            'arn:aws:quicksight:region:account:dataset/dataset-id'
        ]
    },
    'Status': 200
}
```

**Used in:** `list_resources.py`, `clone_and_migrate.py`, `audit_migration.py`

---

### DescribeAnalysisDefinition

Retrieves complete analysis definition (including all visuals, sheets, etc.).

**API Call:**
```python
response = client.describe_analysis_definition(
    AwsAccountId='string',
    AnalysisId='string'
)
```

**Response:**
```python
{
    'AnalysisId': 'string',
    'Name': 'string',
    'Definition': {
        'DataSetIdentifierDeclarations': [...],
        'Sheets': [...],
        'CalculatedFields': [...],
        'ParameterDeclarations': [...],
        'FilterGroups': [...]
    },
    'Status': 200
}
```

**This is crucial for cloning analyses!**

**Used in:** `clone_and_migrate.py`

---

### ListAnalyses

Lists all analyses.

**API Call:**
```python
response = client.list_analyses(
    AwsAccountId='string',
    NextToken='string',
    MaxResults=123
)
```

**Used in:** `list_resources.py`, `audit_migration.py`

---

## Dashboard Operations

### CreateDashboard

Creates or updates a dashboard from an analysis.

**API Call:**
```python
response = client.create_dashboard(
    AwsAccountId='string',
    DashboardId='string',
    Name='string',
    SourceEntity={
        'SourceTemplate': {
            'Arn': 'arn:aws:quicksight:region:account:analysis/analysis-id'
        }
    },
    Permissions=[...],
    VersionDescription='string'
)
```

**Used in:** `clone_and_migrate.py`

---

### DescribeDashboard

Retrieves dashboard metadata.

**API Call:**
```python
response = client.describe_dashboard(
    AwsAccountId='string',
    DashboardId='string',
    VersionNumber=123  # Optional
)
```

**Response:**
```python
{
    'Dashboard': {
        'DashboardId': 'string',
        'Arn': 'string',
        'Name': 'string',
        'Version': {
            'CreatedTime': datetime(2025, 1, 1),
            'VersionNumber': 123,
            'Status': 'CREATION_SUCCESSFUL',
            'DataSetArns': [
                'arn:aws:quicksight:region:account:dataset/dataset-id'
            ]
        },
        'CreatedTime': datetime(2025, 1, 1),
        'LastPublishedTime': datetime(2025, 1, 1),
        'LastUpdatedTime': datetime(2025, 1, 1)
    },
    'Status': 200
}
```

**Used in:** `list_resources.py`, `audit_migration.py`

---

### DescribeDashboardDefinition

Retrieves complete dashboard definition.

**API Call:**
```python
response = client.describe_dashboard_definition(
    AwsAccountId='string',
    DashboardId='string',
    VersionNumber=123  # Optional
)
```

**Used in:** `clone_and_migrate.py`

---

### ListDashboards

Lists all dashboards.

**API Call:**
```python
response = client.list_dashboards(
    AwsAccountId='string',
    NextToken='string',
    MaxResults=123
)
```

**Used in:** `list_resources.py`

---

## Permission Operations

### DescribeDataSetPermissions

Retrieves dataset permissions.

**API Call:**
```python
response = client.describe_data_set_permissions(
    AwsAccountId='string',
    DataSetId='string'
)
```

**Response:**
```python
{
    'DataSetArn': 'string',
    'DataSetId': 'string',
    'Permissions': [
        {
            'Principal': 'arn:aws:quicksight:region:account:user/namespace/username',
            'Actions': [
                'quicksight:DescribeDataSet',
                'quicksight:PassDataSet',
                'quicksight:UpdateDataSet'
            ]
        }
    ],
    'Status': 200
}
```

**Used in:** `migrate_datasets.py` (to copy permissions when cloning)

---

### UpdateDataSetPermissions

Updates dataset permissions.

**API Call:**
```python
response = client.update_data_set_permissions(
    AwsAccountId='string',
    DataSetId='string',
    GrantPermissions=[
        {
            'Principal': 'arn:aws:quicksight:region:account:user/namespace/username',
            'Actions': [
                'quicksight:DescribeDataSet',
                'quicksight:PassDataSet'
            ]
        }
    ],
    RevokePermissions=[...]
)
```

---

## Rate Limiting and Best Practices

### API Rate Limits

QuickSight API has the following rate limits (as of 2025):

| Operation | Rate Limit |
|-----------|-----------|
| CreateDataSource | 5 per second |
| UpdateDataSource | 5 per second |
| CreateDataSet | 5 per second |
| UpdateDataSet | 5 per second |
| CreateAnalysis | 5 per second |
| DescribeDataSet | 20 per second |
| ListDataSets | 5 per second |

### Retry Strategy

Implement exponential backoff for throttled requests:

```python
import time
from botocore.exceptions import ClientError

def call_with_retry(func, max_retries=5):
    for attempt in range(max_retries):
        try:
            return func()
        except ClientError as e:
            if e.response['Error']['Code'] == 'ThrottlingException':
                wait_time = (2 ** attempt) + random.random()
                time.sleep(wait_time)
            else:
                raise
    raise Exception("Max retries exceeded")
```

### Best Practices

1. **Batch Operations**: Process resources in batches with delays
2. **Error Handling**: Always handle `ResourceNotFoundException`, `ThrottlingException`, `InvalidParameterValueException`
3. **Idempotency**: Check if resources exist before creating
4. **Pagination**: Use `NextToken` for listing operations
5. **Credentials**: Use IAM roles instead of hardcoded credentials
6. **Logging**: Enable CloudTrail for auditing API calls

---

## Common Error Codes

| Error Code | Description | Solution |
|-----------|-------------|----------|
| `ResourceNotFoundException` | Resource doesn't exist | Check IDs, ensure resource was created |
| `ResourceExistsException` | Resource already exists | Use update instead of create, or check existing resource |
| `InvalidParameterValueException` | Invalid parameter value | Validate inputs, check API documentation |
| `ThrottlingException` | Rate limit exceeded | Implement exponential backoff |
| `AccessDeniedException` | Insufficient permissions | Check IAM policies and QuickSight permissions |
| `ConflictException` | Resource is being modified | Wait and retry operation |
| `UnsupportedUserEditionException` | Feature not available in edition | Check QuickSight edition (Standard vs Enterprise) |

---

## Example: Complete Dataset Migration

Here's how the dataset migration works at the API level:

```python
# 1. Get old dataset definition
old_dataset = client.describe_data_set(
    AwsAccountId='123456789012',
    DataSetId='sales-aurora-dataset'
)

# 2. Get new data source ARN
new_datasource = client.describe_data_source(
    AwsAccountId='123456789012',
    DataSourceId='redshift-datasource'
)
new_datasource_arn = new_datasource['DataSource']['Arn']

# 3. Update physical table map to use new data source
physical_table_map = old_dataset['DataSet']['PhysicalTableMap']
for table_id, table_config in physical_table_map.items():
    if 'RelationalTable' in table_config:
        table_config['RelationalTable']['DataSourceArn'] = new_datasource_arn

# 4. Update the dataset
response = client.update_data_set(
    AwsAccountId='123456789012',
    DataSetId='sales-aurora-dataset',
    Name=old_dataset['DataSet']['Name'],
    PhysicalTableMap=physical_table_map,
    LogicalTableMap=old_dataset['DataSet']['LogicalTableMap'],
    ImportMode=old_dataset['DataSet']['ImportMode']
)

# 5. All analyses and dashboards now use Redshift automatically!
```

**That's it!** No need to modify analyses or dashboards because they reference the dataset, not the data source.

---

## Additional Resources

- [AWS QuickSight API Reference](https://docs.aws.amazon.com/quicksight/latest/APIReference/)
- [Boto3 QuickSight Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/quicksight.html)
- [QuickSight Developer Guide](https://docs.aws.amazon.com/quicksight/latest/user/welcome.html)

---

## Version Compatibility

This toolkit is compatible with:
- QuickSight API Version: 2018-04-01
- Boto3 Version: >= 1.26.0
- Python Version: >= 3.7
- AWS CLI Version: >= 2.0

Last Updated: December 2025
