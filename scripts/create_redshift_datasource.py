#!/usr/bin/env python3
"""
Create a new Redshift data source in QuickSight.
"""

import boto3
import argparse
import json
from typing import Dict, Any
from botocore.exceptions import ClientError


class RedshiftDataSourceCreator:
    def __init__(self, aws_account_id: str, region: str = None):
        self.aws_account_id = aws_account_id
        self.client = boto3.client('quicksight', region_name=region)
    
    def create_redshift_data_source(
        self,
        data_source_id: str,
        name: str,
        cluster_id: str,
        host: str,
        port: int,
        database: str,
        username: str,
        password: str,
        vpc_connection_arn: str = None
    ) -> Dict[str, Any]:
        """
        Create a new Redshift data source.
        
        Args:
            data_source_id: Unique identifier for the data source
            name: Display name for the data source
            cluster_id: Redshift cluster identifier
            host: Redshift cluster endpoint
            port: Port number (usually 5439)
            database: Database name
            username: Database username
            password: Database password
            vpc_connection_arn: Optional VPC connection ARN for private connectivity
        
        Returns:
            Response from QuickSight API
        """
        params = {
            'AwsAccountId': self.aws_account_id,
            'DataSourceId': data_source_id,
            'Name': name,
            'Type': 'REDSHIFT',
            'DataSourceParameters': {
                'RedshiftParameters': {
                    'Host': host,
                    'Port': port,
                    'Database': database,
                    'ClusterId': cluster_id
                }
            },
            'Credentials': {
                'CredentialPair': {
                    'Username': username,
                    'Password': password
                }
            },
            'Permissions': [
                {
                    'Principal': f'arn:aws:quicksight:{self.client.meta.region_name}:{self.aws_account_id}:user/default/{username}',
                    'Actions': [
                        'quicksight:DescribeDataSource',
                        'quicksight:DescribeDataSourcePermissions',
                        'quicksight:PassDataSource',
                        'quicksight:UpdateDataSource',
                        'quicksight:DeleteDataSource',
                        'quicksight:UpdateDataSourcePermissions'
                    ]
                }
            ]
        }
        
        # Add VPC connection if provided
        if vpc_connection_arn:
            params['VpcConnectionProperties'] = {
                'VpcConnectionArn': vpc_connection_arn
            }
        
        try:
            response = self.client.create_data_source(**params)
            print(f"✅ Successfully created Redshift data source: {data_source_id}")
            print(f"   ARN: {response.get('Arn', 'N/A')}")
            print(f"   Status: {response.get('Status', 'N/A')}")
            return response
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'ResourceExistsException':
                print(f"⚠️  Data source {data_source_id} already exists. Use update instead.")
                return self.update_redshift_data_source(
                    data_source_id, name, cluster_id, host, port, database, username, password, vpc_connection_arn
                )
            else:
                print(f"❌ Error creating data source: {e}")
                raise
    
    def update_redshift_data_source(
        self,
        data_source_id: str,
        name: str,
        cluster_id: str,
        host: str,
        port: int,
        database: str,
        username: str,
        password: str,
        vpc_connection_arn: str = None
    ) -> Dict[str, Any]:
        """Update an existing Redshift data source."""
        params = {
            'AwsAccountId': self.aws_account_id,
            'DataSourceId': data_source_id,
            'Name': name,
            'DataSourceParameters': {
                'RedshiftParameters': {
                    'Host': host,
                    'Port': port,
                    'Database': database,
                    'ClusterId': cluster_id
                }
            },
            'Credentials': {
                'CredentialPair': {
                    'Username': username,
                    'Password': password
                }
            }
        }
        
        if vpc_connection_arn:
            params['VpcConnectionProperties'] = {
                'VpcConnectionArn': vpc_connection_arn
            }
        
        try:
            response = self.client.update_data_source(**params)
            print(f"✅ Successfully updated Redshift data source: {data_source_id}")
            return response
        except ClientError as e:
            print(f"❌ Error updating data source: {e}")
            raise
    
    def create_from_config(self, config_file: str) -> Dict[str, Any]:
        """Create data source from JSON config file."""
        with open(config_file, 'r') as f:
            config = json.load(f)
        
        return self.create_redshift_data_source(
            data_source_id=config['data_source_id'],
            name=config['name'],
            cluster_id=config['cluster_id'],
            host=config['host'],
            port=config.get('port', 5439),
            database=config['database'],
            username=config['username'],
            password=config['password'],
            vpc_connection_arn=config.get('vpc_connection_arn')
        )
    
    def test_connection(self, data_source_id: str) -> bool:
        """Test the data source connection."""
        try:
            response = self.client.describe_data_source(
                AwsAccountId=self.aws_account_id,
                DataSourceId=data_source_id
            )
            status = response['DataSource']['Status']
            
            if status == 'CREATION_SUCCESSFUL':
                print(f"✅ Data source connection test successful!")
                return True
            elif status == 'CREATION_FAILED':
                print(f"❌ Data source connection failed!")
                error_info = response['DataSource'].get('ErrorInfo', {})
                print(f"   Error: {error_info.get('Message', 'Unknown error')}")
                return False
            else:
                print(f"⏳ Data source status: {status}")
                return False
        except ClientError as e:
            print(f"❌ Error testing connection: {e}")
            return False


def main():
    parser = argparse.ArgumentParser(
        description='Create a Redshift data source in QuickSight'
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
        '--config',
        required=True,
        help='Path to JSON configuration file'
    )
    parser.add_argument(
        '--test',
        action='store_true',
        help='Test the connection after creation'
    )
    
    args = parser.parse_args()
    
    creator = RedshiftDataSourceCreator(args.aws_account_id, args.region)
    response = creator.create_from_config(args.config)
    
    if args.test and response:
        import time
        print("\n⏳ Waiting 5 seconds for data source initialization...")
        time.sleep(5)
        creator.test_connection(response.get('DataSourceId'))


if __name__ == '__main__':
    main()
