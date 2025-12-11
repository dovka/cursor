#!/usr/bin/env python3
"""
Clone QuickSight analyses and dashboards, updating their dataset references
to use migrated (Redshift-backed) datasets.
"""

import boto3
import argparse
import time
from typing import Dict, Any, List
from botocore.exceptions import ClientError


class AnalysisDashboardMigrator:
    def __init__(self, aws_account_id: str, region: str = None):
        self.aws_account_id = aws_account_id
        self.client = boto3.client('quicksight', region_name=region)
        self.region = region or boto3.session.Session().region_name
    
    def get_analysis_definition(self, analysis_id: str) -> Dict[str, Any]:
        """Get the full definition of an analysis."""
        try:
            response = self.client.describe_analysis_definition(
                AwsAccountId=self.aws_account_id,
                AnalysisId=analysis_id
            )
            return response
        except ClientError as e:
            print(f"❌ Error getting analysis definition {analysis_id}: {e}")
            raise
    
    def get_dashboard_definition(self, dashboard_id: str) -> Dict[str, Any]:
        """Get the full definition of a dashboard."""
        try:
            response = self.client.describe_dashboard_definition(
                AwsAccountId=self.aws_account_id,
                DashboardId=dashboard_id
            )
            return response
        except ClientError as e:
            print(f"❌ Error getting dashboard definition {dashboard_id}: {e}")
            raise
    
    def replace_dataset_references(
        self,
        definition: Dict[str, Any],
        dataset_mapping: Dict[str, str]
    ) -> Dict[str, Any]:
        """
        Replace dataset references in a definition.
        
        Args:
            definition: Analysis or dashboard definition
            dataset_mapping: Dict mapping old dataset IDs to new dataset IDs
        
        Returns:
            Updated definition
        """
        # Update DataSetIdentifierDeclarations
        if 'DataSetIdentifierDeclarations' in definition:
            for dataset_decl in definition['DataSetIdentifierDeclarations']:
                old_arn = dataset_decl['DataSetArn']
                
                # Extract dataset ID from ARN
                for old_id, new_id in dataset_mapping.items():
                    if old_id in old_arn:
                        # Construct new ARN
                        new_arn = f"arn:aws:quicksight:{self.region}:{self.aws_account_id}:dataset/{new_id}"
                        dataset_decl['DataSetArn'] = new_arn
                        print(f"    ✓ Replaced dataset reference: {old_id} → {new_id}")
                        break
        
        return definition
    
    def clone_analysis(
        self,
        source_analysis_id: str,
        new_analysis_id: str,
        dataset_mapping: Dict[str, str],
        suffix: str = "-redshift"
    ) -> Dict[str, Any]:
        """
        Clone an analysis with updated dataset references.
        
        Args:
            source_analysis_id: ID of the analysis to clone
            new_analysis_id: ID for the new analysis
            dataset_mapping: Dict mapping old dataset IDs to new dataset IDs
            suffix: Suffix to add to the analysis name
        """
        # Get source analysis details
        try:
            source_response = self.client.describe_analysis(
                AwsAccountId=self.aws_account_id,
                AnalysisId=source_analysis_id
            )
            source_analysis = source_response['Analysis']
        except ClientError as e:
            print(f"❌ Error getting analysis: {e}")
            raise
        
        # Get source analysis definition
        definition_response = self.get_analysis_definition(source_analysis_id)
        definition = definition_response.get('Definition', {})
        
        # Replace dataset references
        updated_definition = self.replace_dataset_references(definition, dataset_mapping)
        
        # Create new analysis
        create_params = {
            'AwsAccountId': self.aws_account_id,
            'AnalysisId': new_analysis_id,
            'Name': source_analysis['Name'] + suffix,
            'Definition': updated_definition
        }
        
        # Copy permissions
        try:
            perm_response = self.client.describe_analysis_permissions(
                AwsAccountId=self.aws_account_id,
                AnalysisId=source_analysis_id
            )
            if 'Permissions' in perm_response:
                create_params['Permissions'] = perm_response['Permissions']
        except ClientError:
            pass
        
        try:
            response = self.client.create_analysis(**create_params)
            print(f"  ✅ Successfully cloned analysis as {new_analysis_id}")
            return response
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceExistsException':
                print(f"  ⚠️  Analysis {new_analysis_id} already exists. Skipping.")
                return None
            print(f"  ❌ Error cloning analysis: {e}")
            raise
    
    def clone_dashboard(
        self,
        source_dashboard_id: str,
        new_dashboard_id: str,
        source_analysis_id: str,
        new_analysis_id: str,
        suffix: str = "-redshift"
    ) -> Dict[str, Any]:
        """
        Clone a dashboard referencing a new analysis.
        
        Note: Dashboards are typically published from analyses, so we need
        to reference the new migrated analysis.
        """
        # Get source dashboard details
        try:
            source_response = self.client.describe_dashboard(
                AwsAccountId=self.aws_account_id,
                DashboardId=source_dashboard_id
            )
            source_dashboard = source_response['Dashboard']
        except ClientError as e:
            print(f"❌ Error getting dashboard: {e}")
            raise
        
        # Get the new analysis ARN
        new_source_entity = {
            'SourceTemplate': {
                'Arn': f"arn:aws:quicksight:{self.region}:{self.aws_account_id}:analysis/{new_analysis_id}"
            }
        }
        
        # Create new dashboard
        create_params = {
            'AwsAccountId': self.aws_account_id,
            'DashboardId': new_dashboard_id,
            'Name': source_dashboard['Name'] + suffix,
            'SourceEntity': new_source_entity
        }
        
        # Copy permissions
        try:
            perm_response = self.client.describe_dashboard_permissions(
                AwsAccountId=self.aws_account_id,
                DashboardId=source_dashboard_id
            )
            if 'Permissions' in perm_response:
                create_params['Permissions'] = perm_response['Permissions']
        except ClientError:
            pass
        
        # Copy version description if available
        if 'Version' in source_dashboard and 'Description' in source_dashboard['Version']:
            create_params['VersionDescription'] = source_dashboard['Version']['Description']
        
        try:
            response = self.client.create_dashboard(**create_params)
            print(f"  ✅ Successfully cloned dashboard as {new_dashboard_id}")
            return response
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceExistsException':
                print(f"  ⚠️  Dashboard {new_dashboard_id} already exists. Skipping.")
                return None
            print(f"  ❌ Error cloning dashboard: {e}")
            raise
    
    def migrate_analysis_with_datasets(
        self,
        analysis_id: str,
        dataset_mapping: Dict[str, str],
        suffix: str = "-redshift"
    ):
        """
        Migrate an analysis by cloning it with new dataset references.
        
        Args:
            analysis_id: ID of the analysis to migrate
            dataset_mapping: Dict mapping old dataset IDs to new dataset IDs
            suffix: Suffix for the cloned analysis
        """
        new_analysis_id = f"{analysis_id}{suffix}"
        
        print(f"Migrating analysis: {analysis_id}")
        
        try:
            self.clone_analysis(
                source_analysis_id=analysis_id,
                new_analysis_id=new_analysis_id,
                dataset_mapping=dataset_mapping,
                suffix=suffix
            )
            
            # Wait for analysis creation to complete
            time.sleep(2)
            
            return new_analysis_id
        except Exception as e:
            print(f"  ❌ Failed to migrate analysis: {e}")
            return None


def main():
    parser = argparse.ArgumentParser(
        description='Clone and migrate QuickSight analyses and dashboards'
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
        '--resource-type',
        choices=['analysis', 'dashboard'],
        required=True,
        help='Type of resource to migrate'
    )
    parser.add_argument(
        '--resource-id',
        required=True,
        help='ID of the resource to migrate'
    )
    parser.add_argument(
        '--dataset-mapping',
        required=True,
        help='JSON file with dataset ID mapping (old:new)'
    )
    parser.add_argument(
        '--suffix',
        default='-redshift',
        help='Suffix for cloned resources'
    )
    
    args = parser.parse_args()
    
    # Load dataset mapping
    import json
    with open(args.dataset_mapping, 'r') as f:
        dataset_mapping = json.load(f)
    
    migrator = AnalysisDashboardMigrator(args.aws_account_id, args.region)
    
    if args.resource_type == 'analysis':
        migrator.migrate_analysis_with_datasets(
            analysis_id=args.resource_id,
            dataset_mapping=dataset_mapping,
            suffix=args.suffix
        )
    elif args.resource_type == 'dashboard':
        print("⚠️  Dashboard migration requires the associated analysis to be migrated first.")
        print("   Use the analysis migration option first, then publish a dashboard from the new analysis.")


if __name__ == '__main__':
    main()
