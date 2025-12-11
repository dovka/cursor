#!/usr/bin/env python3
"""
Migrate QuickSight datasets from Aurora to Redshift data sources.

This script supports two modes:
1. UPDATE: Modify existing datasets to use Redshift (in-place)
2. CLONE: Create new datasets with Redshift connection (safer)
"""

import boto3
import argparse
import json
import time
from typing import Dict, Any, List
from botocore.exceptions import ClientError


class DataSetMigrator:
    def __init__(self, aws_account_id: str, region: str = None):
        self.aws_account_id = aws_account_id
        self.client = boto3.client('quicksight', region_name=region)
    
    def get_dataset_definition(self, dataset_id: str) -> Dict[str, Any]:
        """Get the full definition of a dataset."""
        try:
            response = self.client.describe_data_set(
                AwsAccountId=self.aws_account_id,
                DataSetId=dataset_id
            )
            return response['DataSet']
        except ClientError as e:
            print(f"❌ Error getting dataset {dataset_id}: {e}")
            raise
    
    def find_datasets_by_datasource(self, data_source_id: str) -> List[Dict[str, Any]]:
        """Find all datasets that use a specific data source."""
        try:
            response = self.client.list_data_sets(AwsAccountId=self.aws_account_id)
            datasets = []
            
            for ds_summary in response.get('DataSetSummaries', []):
                dataset = self.get_dataset_definition(ds_summary['DataSetId'])
                
                # Check if dataset uses the specified data source
                for table_id, table_config in dataset.get('PhysicalTableMap', {}).items():
                    if 'RelationalTable' in table_config:
                        rel_table = table_config['RelationalTable']
                        if data_source_id in rel_table.get('DataSourceArn', ''):
                            datasets.append(dataset)
                            break
            
            return datasets
        except ClientError as e:
            print(f"❌ Error finding datasets: {e}")
            return []
    
    def update_dataset_datasource(
        self,
        dataset_id: str,
        old_datasource_id: str,
        new_datasource_id: str,
        new_datasource_arn: str = None
    ) -> Dict[str, Any]:
        """
        Update a dataset to use a new data source.
        
        Args:
            dataset_id: ID of the dataset to update
            old_datasource_id: Current data source ID
            new_datasource_id: New Redshift data source ID
            new_datasource_arn: Optional ARN of new data source (will be fetched if not provided)
        """
        # Get current dataset definition
        dataset = self.get_dataset_definition(dataset_id)
        
        # Get new data source ARN if not provided
        if not new_datasource_arn:
            try:
                ds_response = self.client.describe_data_source(
                    AwsAccountId=self.aws_account_id,
                    DataSourceId=new_datasource_id
                )
                new_datasource_arn = ds_response['DataSource']['Arn']
            except ClientError as e:
                print(f"❌ Error getting new data source ARN: {e}")
                raise
        
        # Update PhysicalTableMap to use new data source
        physical_table_map = dataset.get('PhysicalTableMap', {})
        updated = False
        
        for table_id, table_config in physical_table_map.items():
            if 'RelationalTable' in table_config:
                rel_table = table_config['RelationalTable']
                if old_datasource_id in rel_table.get('DataSourceArn', ''):
                    rel_table['DataSourceArn'] = new_datasource_arn
                    updated = True
                    print(f"  ✓ Updated table '{table_id}' to use new data source")
        
        if not updated:
            print(f"  ⚠️  No tables found using data source {old_datasource_id}")
            return None
        
        # Prepare update parameters
        update_params = {
            'AwsAccountId': self.aws_account_id,
            'DataSetId': dataset_id,
            'Name': dataset['Name'],
            'PhysicalTableMap': physical_table_map,
            'ImportMode': dataset['ImportMode']
        }
        
        # Add optional parameters if they exist
        if 'LogicalTableMap' in dataset:
            update_params['LogicalTableMap'] = dataset['LogicalTableMap']
        
        if 'ColumnGroups' in dataset:
            update_params['ColumnGroups'] = dataset['ColumnGroups']
        
        if 'FieldFolders' in dataset:
            update_params['FieldFolders'] = dataset['FieldFolders']
        
        if 'RowLevelPermissionDataSet' in dataset:
            update_params['RowLevelPermissionDataSet'] = dataset['RowLevelPermissionDataSet']
        
        if 'ColumnLevelPermissionRules' in dataset:
            update_params['ColumnLevelPermissionRules'] = dataset['ColumnLevelPermissionRules']
        
        try:
            response = self.client.update_data_set(**update_params)
            print(f"  ✅ Successfully updated dataset {dataset_id}")
            return response
        except ClientError as e:
            print(f"  ❌ Error updating dataset {dataset_id}: {e}")
            raise
    
    def clone_dataset_with_new_datasource(
        self,
        source_dataset_id: str,
        new_dataset_id: str,
        new_datasource_id: str,
        old_datasource_id: str,
        suffix: str = "-redshift"
    ) -> Dict[str, Any]:
        """
        Clone a dataset and update it to use a new data source.
        
        Args:
            source_dataset_id: ID of the dataset to clone
            new_dataset_id: ID for the new dataset
            new_datasource_id: New Redshift data source ID
            old_datasource_id: Current Aurora data source ID to replace
            suffix: Suffix to add to the dataset name
        """
        # Get source dataset
        source_dataset = self.get_dataset_definition(source_dataset_id)
        
        # Get new data source ARN
        try:
            ds_response = self.client.describe_data_source(
                AwsAccountId=self.aws_account_id,
                DataSourceId=new_datasource_id
            )
            new_datasource_arn = ds_response['DataSource']['Arn']
        except ClientError as e:
            print(f"❌ Error getting new data source ARN: {e}")
            raise
        
        # Update PhysicalTableMap to use new data source
        physical_table_map = source_dataset.get('PhysicalTableMap', {})
        for table_id, table_config in physical_table_map.items():
            if 'RelationalTable' in table_config:
                rel_table = table_config['RelationalTable']
                if old_datasource_id in rel_table.get('DataSourceArn', ''):
                    rel_table['DataSourceArn'] = new_datasource_arn
        
        # Prepare create parameters
        create_params = {
            'AwsAccountId': self.aws_account_id,
            'DataSetId': new_dataset_id,
            'Name': source_dataset['Name'] + suffix,
            'PhysicalTableMap': physical_table_map,
            'ImportMode': source_dataset['ImportMode']
        }
        
        # Add optional parameters
        if 'LogicalTableMap' in source_dataset:
            create_params['LogicalTableMap'] = source_dataset['LogicalTableMap']
        
        if 'ColumnGroups' in source_dataset:
            create_params['ColumnGroups'] = source_dataset['ColumnGroups']
        
        if 'FieldFolders' in source_dataset:
            create_params['FieldFolders'] = source_dataset['FieldFolders']
        
        # Copy permissions from source
        try:
            perm_response = self.client.describe_data_set_permissions(
                AwsAccountId=self.aws_account_id,
                DataSetId=source_dataset_id
            )
            if 'Permissions' in perm_response:
                create_params['Permissions'] = perm_response['Permissions']
        except ClientError:
            pass  # Permissions are optional
        
        try:
            response = self.client.create_data_set(**create_params)
            print(f"  ✅ Successfully cloned dataset as {new_dataset_id}")
            return response
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceExistsException':
                print(f"  ⚠️  Dataset {new_dataset_id} already exists. Skipping.")
                return None
            print(f"  ❌ Error cloning dataset: {e}")
            raise
    
    def migrate_datasets(
        self,
        source_datasource_id: str,
        target_datasource_id: str,
        mode: str = 'update',
        suffix: str = '-redshift',
        dataset_ids: List[str] = None
    ):
        """
        Migrate datasets from Aurora to Redshift.
        
        Args:
            source_datasource_id: Aurora data source ID
            target_datasource_id: Redshift data source ID
            mode: 'update' (in-place) or 'clone' (create new datasets)
            suffix: Suffix for cloned datasets (only used in clone mode)
            dataset_ids: Optional list of specific dataset IDs to migrate
        """
        print("=" * 80)
        print(f"Dataset Migration: {source_datasource_id} → {target_datasource_id}")
        print(f"Mode: {mode.upper()}")
        print("=" * 80)
        
        # Find datasets to migrate
        if dataset_ids:
            datasets = [self.get_dataset_definition(ds_id) for ds_id in dataset_ids]
        else:
            datasets = self.find_datasets_by_datasource(source_datasource_id)
        
        if not datasets:
            print("\n⚠️  No datasets found using the specified data source.")
            return
        
        print(f"\n📦 Found {len(datasets)} dataset(s) to migrate:\n")
        
        success_count = 0
        error_count = 0
        
        for dataset in datasets:
            dataset_id = dataset['DataSetId']
            dataset_name = dataset['Name']
            
            print(f"Processing: {dataset_name} (ID: {dataset_id})")
            
            try:
                if mode == 'update':
                    result = self.update_dataset_datasource(
                        dataset_id=dataset_id,
                        old_datasource_id=source_datasource_id,
                        new_datasource_id=target_datasource_id
                    )
                    if result:
                        success_count += 1
                
                elif mode == 'clone':
                    new_dataset_id = f"{dataset_id}{suffix}"
                    result = self.clone_dataset_with_new_datasource(
                        source_dataset_id=dataset_id,
                        new_dataset_id=new_dataset_id,
                        new_datasource_id=target_datasource_id,
                        old_datasource_id=source_datasource_id,
                        suffix=suffix
                    )
                    if result:
                        success_count += 1
                
                time.sleep(0.5)  # Rate limiting
                
            except Exception as e:
                print(f"  ❌ Failed to process dataset: {e}")
                error_count += 1
            
            print()
        
        print("=" * 80)
        print(f"Migration Complete:")
        print(f"  ✅ Successful: {success_count}")
        print(f"  ❌ Failed: {error_count}")
        print("=" * 80)


def main():
    parser = argparse.ArgumentParser(
        description='Migrate QuickSight datasets from Aurora to Redshift'
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
        '--source-id',
        required=True,
        help='Source Aurora data source ID'
    )
    parser.add_argument(
        '--target-id',
        required=True,
        help='Target Redshift data source ID'
    )
    parser.add_argument(
        '--mode',
        choices=['update', 'clone'],
        default='clone',
        help='Migration mode: update (in-place) or clone (create new)'
    )
    parser.add_argument(
        '--suffix',
        default='-redshift',
        help='Suffix for cloned datasets (clone mode only)'
    )
    parser.add_argument(
        '--dataset-ids',
        nargs='+',
        help='Specific dataset IDs to migrate (optional)'
    )
    
    args = parser.parse_args()
    
    if args.mode == 'update':
        confirm = input(
            "⚠️  UPDATE mode will modify datasets in-place. "
            "This cannot be easily undone. Continue? (yes/no): "
        )
        if confirm.lower() != 'yes':
            print("Aborted.")
            return
    
    migrator = DataSetMigrator(args.aws_account_id, args.region)
    migrator.migrate_datasets(
        source_datasource_id=args.source_id,
        target_datasource_id=args.target_id,
        mode=args.mode,
        suffix=args.suffix,
        dataset_ids=args.dataset_ids
    )


if __name__ == '__main__':
    main()
