#!/usr/bin/env python3
"""
List all QuickSight resources (data sources, datasets, analyses, dashboards)
and their dependencies to help plan the migration.
"""

import boto3
import argparse
import json
from typing import Dict, List, Any
from botocore.exceptions import ClientError


class QuickSightResourceLister:
    def __init__(self, aws_account_id: str, region: str = None):
        self.aws_account_id = aws_account_id
        self.client = boto3.client('quicksight', region_name=region)
    
    def list_data_sources(self) -> List[Dict[str, Any]]:
        """List all data sources in the account."""
        try:
            response = self.client.list_data_sources(AwsAccountId=self.aws_account_id)
            data_sources = response.get('DataSources', [])
            
            # Get detailed info for each data source
            detailed_sources = []
            for ds in data_sources:
                try:
                    detail = self.client.describe_data_source(
                        AwsAccountId=self.aws_account_id,
                        DataSourceId=ds['DataSourceId']
                    )
                    detailed_sources.append(detail['DataSource'])
                except ClientError as e:
                    print(f"Warning: Could not get details for data source {ds['DataSourceId']}: {e}")
                    detailed_sources.append(ds)
            
            return detailed_sources
        except ClientError as e:
            print(f"Error listing data sources: {e}")
            return []
    
    def list_datasets(self) -> List[Dict[str, Any]]:
        """List all datasets in the account."""
        try:
            response = self.client.list_data_sets(AwsAccountId=self.aws_account_id)
            datasets = response.get('DataSetSummaries', [])
            
            # Get detailed info for each dataset
            detailed_datasets = []
            for ds in datasets:
                try:
                    detail = self.client.describe_data_set(
                        AwsAccountId=self.aws_account_id,
                        DataSetId=ds['DataSetId']
                    )
                    detailed_datasets.append(detail['DataSet'])
                except ClientError as e:
                    print(f"Warning: Could not get details for dataset {ds['DataSetId']}: {e}")
                    detailed_datasets.append(ds)
            
            return detailed_datasets
        except ClientError as e:
            print(f"Error listing datasets: {e}")
            return []
    
    def list_analyses(self) -> List[Dict[str, Any]]:
        """List all analyses in the account."""
        try:
            response = self.client.list_analyses(AwsAccountId=self.aws_account_id)
            return response.get('AnalysisSummaryList', [])
        except ClientError as e:
            print(f"Error listing analyses: {e}")
            return []
    
    def list_dashboards(self) -> List[Dict[str, Any]]:
        """List all dashboards in the account."""
        try:
            response = self.client.list_dashboards(AwsAccountId=self.aws_account_id)
            return response.get('DashboardSummaryList', [])
        except ClientError as e:
            print(f"Error listing dashboards: {e}")
            return []
    
    def get_dataset_dependencies(self, dataset_id: str) -> Dict[str, Any]:
        """Get analyses and dashboards that depend on a specific dataset."""
        dependencies = {
            'analyses': [],
            'dashboards': []
        }
        
        # Check analyses
        analyses = self.list_analyses()
        for analysis in analyses:
            try:
                detail = self.client.describe_analysis(
                    AwsAccountId=self.aws_account_id,
                    AnalysisId=analysis['AnalysisId']
                )
                dataset_arns = [ds['DataSetArn'] for ds in detail['Analysis'].get('DataSetArns', [])]
                if any(dataset_id in arn for arn in dataset_arns):
                    dependencies['analyses'].append(analysis)
            except ClientError:
                pass
        
        # Check dashboards
        dashboards = self.list_dashboards()
        for dashboard in dashboards:
            try:
                detail = self.client.describe_dashboard(
                    AwsAccountId=self.aws_account_id,
                    DashboardId=dashboard['DashboardId']
                )
                # Dashboards are typically created from analyses
                # Check version info for dataset references
                if 'Version' in detail['Dashboard']:
                    dataset_arns = detail['Dashboard']['Version'].get('DataSetArns', [])
                    if any(dataset_id in arn for arn in dataset_arns):
                        dependencies['dashboards'].append(dashboard)
            except ClientError:
                pass
        
        return dependencies
    
    def print_aurora_resources(self, filter_type: str = None):
        """Print resources that use Aurora data sources."""
        print("=" * 80)
        print("QuickSight Resources Using Aurora PostgreSQL")
        print("=" * 80)
        
        # Get all data sources
        data_sources = self.list_data_sources()
        aurora_sources = [
            ds for ds in data_sources 
            if ds.get('Type') in ['AURORA_POSTGRESQL', 'POSTGRESQL', 'AURORA']
        ]
        
        if not aurora_sources:
            print("\nNo Aurora data sources found.")
            return
        
        print(f"\n📊 Found {len(aurora_sources)} Aurora/PostgreSQL Data Source(s):")
        print("-" * 80)
        
        for ds in aurora_sources:
            print(f"\n  ID: {ds['DataSourceId']}")
            print(f"  Name: {ds.get('Name', 'N/A')}")
            print(f"  Type: {ds['Type']}")
            print(f"  ARN: {ds['Arn']}")
            if 'DataSourceParameters' in ds:
                params = ds['DataSourceParameters']
                if 'AuroraPostgreSqlParameters' in params:
                    print(f"  Host: {params['AuroraPostgreSqlParameters'].get('Host', 'N/A')}")
                    print(f"  Database: {params['AuroraPostgreSqlParameters'].get('Database', 'N/A')}")
                elif 'PostgreSqlParameters' in params:
                    print(f"  Host: {params['PostgreSqlParameters'].get('Host', 'N/A')}")
                    print(f"  Database: {params['PostgreSqlParameters'].get('Database', 'N/A')}")
            
            # Find datasets using this data source
            datasets = self.list_datasets()
            related_datasets = [
                d for d in datasets 
                if any(
                    ds['DataSourceId'] in source.get('DataSourceArn', '') 
                    for source in d.get('PhysicalTableMap', {}).values()
                    if 'RelationalTable' in source
                )
            ]
            
            if related_datasets:
                print(f"\n  📦 Datasets using this data source ({len(related_datasets)}):")
                for dataset in related_datasets:
                    print(f"    - {dataset['Name']} (ID: {dataset['DataSetId']})")
                    
                    # Get dependencies for this dataset
                    deps = self.get_dataset_dependencies(dataset['DataSetId'])
                    if deps['analyses']:
                        print(f"      📈 Analyses ({len(deps['analyses'])}):")
                        for analysis in deps['analyses']:
                            print(f"        * {analysis.get('Name', 'N/A')} (ID: {analysis['AnalysisId']})")
                    
                    if deps['dashboards']:
                        print(f"      📊 Dashboards ({len(deps['dashboards'])}):")
                        for dashboard in deps['dashboards']:
                            print(f"        * {dashboard.get('Name', 'N/A')} (ID: {dashboard['DashboardId']})")
        
        print("\n" + "=" * 80)
    
    def export_to_json(self, output_file: str):
        """Export all resources to JSON file for further processing."""
        data = {
            'data_sources': self.list_data_sources(),
            'datasets': self.list_datasets(),
            'analyses': self.list_analyses(),
            'dashboards': self.list_dashboards()
        }
        
        with open(output_file, 'w') as f:
            json.dump(data, f, indent=2, default=str)
        
        print(f"✅ Exported resource inventory to {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description='List QuickSight resources and their dependencies'
    )
    parser.add_argument(
        '--aws-account-id',
        required=True,
        help='AWS Account ID'
    )
    parser.add_argument(
        '--region',
        default=None,
        help='AWS Region (default: uses AWS CLI configuration)'
    )
    parser.add_argument(
        '--export',
        help='Export resources to JSON file'
    )
    parser.add_argument(
        '--filter',
        choices=['aurora', 'all'],
        default='aurora',
        help='Filter resources (default: aurora)'
    )
    
    args = parser.parse_args()
    
    lister = QuickSightResourceLister(args.aws_account_id, args.region)
    
    if args.filter == 'aurora':
        lister.print_aurora_resources()
    
    if args.export:
        lister.export_to_json(args.export)


if __name__ == '__main__':
    main()
