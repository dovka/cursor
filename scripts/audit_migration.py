#!/usr/bin/env python3
"""
Audit and verify QuickSight migration from Aurora to Redshift.
Checks for:
- Data source connectivity
- Dataset schema compatibility
- Missing references
- Permission issues
"""

import boto3
import argparse
import json
from typing import Dict, Any, List, Tuple
from botocore.exceptions import ClientError


class MigrationAuditor:
    def __init__(self, aws_account_id: str, region: str = None):
        self.aws_account_id = aws_account_id
        self.client = boto3.client('quicksight', region_name=region)
        self.issues = []
        self.warnings = []
    
    def check_data_source_status(self, data_source_id: str) -> Tuple[bool, str]:
        """Check if a data source is healthy."""
        try:
            response = self.client.describe_data_source(
                AwsAccountId=self.aws_account_id,
                DataSourceId=data_source_id
            )
            status = response['DataSource']['Status']
            
            if status == 'CREATION_SUCCESSFUL':
                return True, "OK"
            elif status == 'CREATION_FAILED':
                error_info = response['DataSource'].get('ErrorInfo', {})
                return False, f"Failed: {error_info.get('Message', 'Unknown error')}"
            else:
                return False, f"Status: {status}"
        except ClientError as e:
            return False, f"Error: {str(e)}"
    
    def check_dataset_status(self, dataset_id: str) -> Tuple[bool, str, Dict]:
        """Check if a dataset is healthy and get its metadata."""
        try:
            response = self.client.describe_data_set(
                AwsAccountId=self.aws_account_id,
                DataSetId=dataset_id
            )
            dataset = response['DataSet']
            
            # Check if dataset has any errors
            if 'ErrorInfo' in dataset:
                return False, f"Error: {dataset['ErrorInfo'].get('Message', 'Unknown')}", dataset
            
            # Extract data source references
            data_sources = []
            for table_id, table_config in dataset.get('PhysicalTableMap', {}).items():
                if 'RelationalTable' in table_config:
                    ds_arn = table_config['RelationalTable'].get('DataSourceArn', '')
                    data_sources.append(ds_arn)
            
            return True, "OK", {'data_sources': data_sources, 'name': dataset['Name']}
        except ClientError as e:
            return False, f"Error: {str(e)}", {}
    
    def check_analysis_status(self, analysis_id: str) -> Tuple[bool, str, List[str]]:
        """Check if an analysis is healthy and get its dataset dependencies."""
        try:
            response = self.client.describe_analysis(
                AwsAccountId=self.aws_account_id,
                AnalysisId=analysis_id
            )
            analysis = response['Analysis']
            dataset_arns = analysis.get('DataSetArns', [])
            
            # Extract dataset IDs from ARNs
            dataset_ids = [arn.split('/')[-1] for arn in dataset_arns]
            
            status = analysis.get('Status')
            if status == 'CREATION_SUCCESSFUL' or status == 'UPDATE_SUCCESSFUL':
                return True, "OK", dataset_ids
            else:
                return False, f"Status: {status}", dataset_ids
        except ClientError as e:
            return False, f"Error: {str(e)}", []
    
    def check_dashboard_status(self, dashboard_id: str) -> Tuple[bool, str]:
        """Check if a dashboard is healthy."""
        try:
            response = self.client.describe_dashboard(
                AwsAccountId=self.aws_account_id,
                DashboardId=dashboard_id
            )
            dashboard = response['Dashboard']
            
            if 'Version' in dashboard:
                status = dashboard['Version'].get('Status')
                if status == 'CREATION_SUCCESSFUL':
                    return True, "OK"
                else:
                    return False, f"Status: {status}"
            
            return True, "OK"
        except ClientError as e:
            return False, f"Error: {str(e)}"
    
    def audit_redshift_datasource(self, data_source_id: str):
        """Audit a Redshift data source."""
        print(f"\n🔍 Auditing Redshift Data Source: {data_source_id}")
        print("-" * 80)
        
        is_healthy, message = self.check_data_source_status(data_source_id)
        
        if is_healthy:
            print(f"  ✅ Status: {message}")
        else:
            print(f"  ❌ Status: {message}")
            self.issues.append(f"Data source {data_source_id}: {message}")
        
        # Get data source details
        try:
            response = self.client.describe_data_source(
                AwsAccountId=self.aws_account_id,
                DataSourceId=data_source_id
            )
            ds = response['DataSource']
            
            print(f"  Name: {ds.get('Name', 'N/A')}")
            print(f"  Type: {ds.get('Type', 'N/A')}")
            
            if 'DataSourceParameters' in ds and 'RedshiftParameters' in ds['DataSourceParameters']:
                params = ds['DataSourceParameters']['RedshiftParameters']
                print(f"  Cluster: {params.get('ClusterId', 'N/A')}")
                print(f"  Database: {params.get('Database', 'N/A')}")
                print(f"  Host: {params.get('Host', 'N/A')}")
        except ClientError as e:
            print(f"  ⚠️  Could not get details: {e}")
    
    def audit_migrated_datasets(self, data_source_id: str):
        """Audit datasets using a specific data source."""
        print(f"\n🔍 Auditing Datasets Using Data Source: {data_source_id}")
        print("-" * 80)
        
        try:
            # List all datasets
            response = self.client.list_data_sets(AwsAccountId=self.aws_account_id)
            datasets = response.get('DataSetSummaries', [])
            
            related_datasets = []
            for ds in datasets:
                is_healthy, message, metadata = self.check_dataset_status(ds['DataSetId'])
                
                # Check if dataset uses the specified data source
                if any(data_source_id in ds_arn for ds_arn in metadata.get('data_sources', [])):
                    related_datasets.append({
                        'id': ds['DataSetId'],
                        'name': ds.get('Name', 'N/A'),
                        'healthy': is_healthy,
                        'message': message
                    })
            
            if not related_datasets:
                print("  ℹ️  No datasets found using this data source.")
                return
            
            print(f"\n  Found {len(related_datasets)} dataset(s):\n")
            
            healthy_count = 0
            for ds in related_datasets:
                if ds['healthy']:
                    print(f"  ✅ {ds['name']} (ID: {ds['id']})")
                    healthy_count += 1
                else:
                    print(f"  ❌ {ds['name']} (ID: {ds['id']})")
                    print(f"     Issue: {ds['message']}")
                    self.issues.append(f"Dataset {ds['id']}: {ds['message']}")
            
            print(f"\n  Summary: {healthy_count}/{len(related_datasets)} datasets healthy")
            
        except ClientError as e:
            print(f"  ❌ Error auditing datasets: {e}")
    
    def audit_dependent_analyses(self, dataset_ids: List[str]):
        """Audit analyses that depend on specific datasets."""
        print(f"\n🔍 Auditing Dependent Analyses")
        print("-" * 80)
        
        try:
            response = self.client.list_analyses(AwsAccountId=self.aws_account_id)
            analyses = response.get('AnalysisSummaryList', [])
            
            dependent_analyses = []
            for analysis in analyses:
                is_healthy, message, analysis_datasets = self.check_analysis_status(analysis['AnalysisId'])
                
                # Check if analysis uses any of the specified datasets
                if any(ds_id in analysis_datasets for ds_id in dataset_ids):
                    dependent_analyses.append({
                        'id': analysis['AnalysisId'],
                        'name': analysis.get('Name', 'N/A'),
                        'healthy': is_healthy,
                        'message': message,
                        'datasets': analysis_datasets
                    })
            
            if not dependent_analyses:
                print("  ℹ️  No analyses found using the specified datasets.")
                return
            
            print(f"\n  Found {len(dependent_analyses)} analysis/analyses:\n")
            
            healthy_count = 0
            for analysis in dependent_analyses:
                if analysis['healthy']:
                    print(f"  ✅ {analysis['name']} (ID: {analysis['id']})")
                    healthy_count += 1
                else:
                    print(f"  ❌ {analysis['name']} (ID: {analysis['id']})")
                    print(f"     Issue: {analysis['message']}")
                    self.issues.append(f"Analysis {analysis['id']}: {analysis['message']}")
                
                print(f"     Uses datasets: {', '.join(analysis['datasets'])}")
            
            print(f"\n  Summary: {healthy_count}/{len(dependent_analyses)} analyses healthy")
            
        except ClientError as e:
            print(f"  ❌ Error auditing analyses: {e}")
    
    def compare_datasets(self, old_dataset_id: str, new_dataset_id: str):
        """Compare schemas between old and new datasets."""
        print(f"\n🔍 Comparing Datasets")
        print("-" * 80)
        print(f"  Old (Aurora): {old_dataset_id}")
        print(f"  New (Redshift): {new_dataset_id}")
        print()
        
        try:
            # Get old dataset
            old_response = self.client.describe_data_set(
                AwsAccountId=self.aws_account_id,
                DataSetId=old_dataset_id
            )
            old_ds = old_response['DataSet']
            
            # Get new dataset
            new_response = self.client.describe_data_set(
                AwsAccountId=self.aws_account_id,
                DataSetId=new_dataset_id
            )
            new_ds = new_response['DataSet']
            
            # Compare physical table map
            old_tables = set(old_ds.get('PhysicalTableMap', {}).keys())
            new_tables = set(new_ds.get('PhysicalTableMap', {}).keys())
            
            if old_tables == new_tables:
                print(f"  ✅ Physical tables match ({len(old_tables)} tables)")
            else:
                print(f"  ⚠️  Physical tables differ:")
                print(f"     Old: {old_tables}")
                print(f"     New: {new_tables}")
                self.warnings.append(f"Dataset physical tables differ: {old_dataset_id} vs {new_dataset_id}")
            
            # Compare logical table map
            old_logical = set(old_ds.get('LogicalTableMap', {}).keys())
            new_logical = set(new_ds.get('LogicalTableMap', {}).keys())
            
            if old_logical == new_logical:
                print(f"  ✅ Logical tables match ({len(old_logical)} tables)")
            else:
                print(f"  ⚠️  Logical tables differ:")
                print(f"     Old: {old_logical}")
                print(f"     New: {new_logical}")
                self.warnings.append(f"Dataset logical tables differ: {old_dataset_id} vs {new_dataset_id}")
            
            # Compare column counts
            old_cols = len(old_ds.get('OutputColumns', []))
            new_cols = len(new_ds.get('OutputColumns', []))
            
            if old_cols == new_cols:
                print(f"  ✅ Column count matches ({old_cols} columns)")
            else:
                print(f"  ⚠️  Column counts differ: {old_cols} vs {new_cols}")
                self.warnings.append(f"Dataset column counts differ: {old_dataset_id} ({old_cols}) vs {new_dataset_id} ({new_cols})")
            
        except ClientError as e:
            print(f"  ❌ Error comparing datasets: {e}")
    
    def generate_report(self):
        """Generate a summary report of the audit."""
        print("\n" + "=" * 80)
        print("AUDIT REPORT")
        print("=" * 80)
        
        if not self.issues and not self.warnings:
            print("\n✅ All checks passed! No issues or warnings found.")
        else:
            if self.issues:
                print(f"\n❌ Found {len(self.issues)} issue(s):")
                for i, issue in enumerate(self.issues, 1):
                    print(f"  {i}. {issue}")
            
            if self.warnings:
                print(f"\n⚠️  Found {len(self.warnings)} warning(s):")
                for i, warning in enumerate(self.warnings, 1):
                    print(f"  {i}. {warning}")
        
        print("\n" + "=" * 80)


def main():
    parser = argparse.ArgumentParser(
        description='Audit QuickSight migration from Aurora to Redshift'
    )
    parser.add_argument(
        '--aws-account-id',
        required=True,
        help='AWS Account ID'
    )
    parser.add_argument(
        '--region',
        default=None,
        help='AWS Region'
    )
    parser.add_argument(
        '--redshift-datasource-id',
        required=True,
        help='Redshift data source ID to audit'
    )
    parser.add_argument(
        '--compare-datasets',
        nargs=2,
        metavar=('OLD_ID', 'NEW_ID'),
        help='Compare two datasets (old vs new)'
    )
    
    args = parser.parse_args()
    
    auditor = MigrationAuditor(args.aws_account_id, args.region)
    
    # Audit Redshift data source
    auditor.audit_redshift_datasource(args.redshift_datasource_id)
    
    # Audit datasets
    auditor.audit_migrated_datasets(args.redshift_datasource_id)
    
    # Get dataset IDs for dependent analysis audit
    try:
        response = auditor.client.list_data_sets(AwsAccountId=args.aws_account_id)
        dataset_ids = []
        for ds in response.get('DataSetSummaries', []):
            _, _, metadata = auditor.check_dataset_status(ds['DataSetId'])
            if any(args.redshift_datasource_id in ds_arn for ds_arn in metadata.get('data_sources', [])):
                dataset_ids.append(ds['DataSetId'])
        
        if dataset_ids:
            auditor.audit_dependent_analyses(dataset_ids)
    except Exception as e:
        print(f"⚠️  Could not audit dependent analyses: {e}")
    
    # Compare datasets if specified
    if args.compare_datasets:
        auditor.compare_datasets(args.compare_datasets[0], args.compare_datasets[1])
    
    # Generate report
    auditor.generate_report()


if __name__ == '__main__':
    main()
