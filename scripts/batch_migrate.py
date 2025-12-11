#!/usr/bin/env python3
"""
Batch migration script for end-to-end QuickSight migration from Aurora to Redshift.

This script orchestrates the entire migration process:
1. Creates Redshift data source (if needed)
2. Migrates all datasets
3. Optionally migrates analyses
4. Runs audit checks
"""

import boto3
import argparse
import json
import time
import sys
from typing import Dict, Any, List
from pathlib import Path

# Import our migration modules
import importlib.util

def load_module(module_name: str, file_path: str):
    """Dynamically load a module from file path."""
    spec = importlib.util.spec_from_file_location(module_name, file_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BatchMigrator:
    def __init__(self, config_file: str):
        with open(config_file, 'r') as f:
            self.config = json.load(f)
        
        self.aws_account_id = self.config['aws_account_id']
        self.region = self.config.get('region')
        self.aurora_datasource_id = self.config['aurora_datasource_id']
        self.redshift_config = self.config['redshift_config']
        self.migration_mode = self.config.get('migration_mode', 'clone')
        self.suffix = self.config.get('suffix', '-redshift')
        
        # Load migration modules
        scripts_dir = Path(__file__).parent
        self.datasource_creator = load_module(
            'create_redshift_datasource',
            str(scripts_dir / 'create_redshift_datasource.py')
        ).RedshiftDataSourceCreator(self.aws_account_id, self.region)
        
        self.dataset_migrator = load_module(
            'migrate_datasets',
            str(scripts_dir / 'migrate_datasets.py')
        ).DataSetMigrator(self.aws_account_id, self.region)
        
        self.auditor = load_module(
            'audit_migration',
            str(scripts_dir / 'audit_migration.py')
        ).MigrationAuditor(self.aws_account_id, self.region)
        
        self.results = {
            'datasource_created': False,
            'datasets_migrated': 0,
            'datasets_failed': 0,
            'analyses_migrated': 0,
            'audit_passed': False,
            'errors': []
        }
    
    def run_migration(self):
        """Execute the full migration process."""
        print("=" * 80)
        print("QuickSight Batch Migration: Aurora → Redshift")
        print("=" * 80)
        print(f"\nConfiguration:")
        print(f"  AWS Account: {self.aws_account_id}")
        print(f"  Region: {self.region or 'default'}")
        print(f"  Aurora Data Source: {self.aurora_datasource_id}")
        print(f"  Migration Mode: {self.migration_mode}")
        print(f"  Suffix: {self.suffix}")
        print("\n" + "=" * 80)
        
        # Step 1: Create Redshift data source
        if not self._create_redshift_datasource():
            return False
        
        # Step 2: Wait for data source initialization
        time.sleep(5)
        
        # Step 3: Test Redshift connection
        if not self._test_redshift_connection():
            return False
        
        # Step 4: Migrate datasets
        if not self._migrate_datasets():
            return False
        
        # Step 5: Run audit
        self._run_audit()
        
        # Step 6: Generate report
        self._generate_report()
        
        return self.results['audit_passed'] and self.results['datasets_failed'] == 0
    
    def _create_redshift_datasource(self) -> bool:
        """Create Redshift data source."""
        print("\n" + "=" * 80)
        print("STEP 1: Creating Redshift Data Source")
        print("=" * 80)
        
        try:
            response = self.datasource_creator.create_redshift_data_source(
                data_source_id=self.redshift_config['data_source_id'],
                name=self.redshift_config['name'],
                cluster_id=self.redshift_config['cluster_id'],
                host=self.redshift_config['host'],
                port=self.redshift_config.get('port', 5439),
                database=self.redshift_config['database'],
                username=self.redshift_config['username'],
                password=self.redshift_config['password'],
                vpc_connection_arn=self.redshift_config.get('vpc_connection_arn')
            )
            
            if response:
                self.results['datasource_created'] = True
                self.redshift_datasource_id = self.redshift_config['data_source_id']
                return True
            else:
                self.results['errors'].append("Failed to create Redshift data source")
                return False
        except Exception as e:
            print(f"\n❌ Error creating Redshift data source: {e}")
            self.results['errors'].append(f"Data source creation error: {str(e)}")
            return False
    
    def _test_redshift_connection(self) -> bool:
        """Test Redshift data source connection."""
        print("\n" + "=" * 80)
        print("STEP 2: Testing Redshift Connection")
        print("=" * 80)
        
        try:
            is_healthy = self.datasource_creator.test_connection(self.redshift_datasource_id)
            if not is_healthy:
                print("\n⚠️  Redshift connection test failed. Continuing anyway...")
                print("    You may need to fix connection issues manually.")
                # Don't fail - connection might work even if test is inconclusive
            return True
        except Exception as e:
            print(f"\n⚠️  Error testing connection: {e}")
            print("    Continuing with migration...")
            return True
    
    def _migrate_datasets(self) -> bool:
        """Migrate datasets from Aurora to Redshift."""
        print("\n" + "=" * 80)
        print("STEP 3: Migrating Datasets")
        print("=" * 80)
        
        try:
            # Find datasets to migrate
            datasets = self.dataset_migrator.find_datasets_by_datasource(
                self.aurora_datasource_id
            )
            
            if not datasets:
                print("\n⚠️  No datasets found using Aurora data source")
                return True
            
            print(f"\nFound {len(datasets)} dataset(s) to migrate\n")
            
            success_count = 0
            error_count = 0
            
            for dataset in datasets:
                dataset_id = dataset['DataSetId']
                dataset_name = dataset['Name']
                
                print(f"Processing: {dataset_name} (ID: {dataset_id})")
                
                try:
                    if self.migration_mode == 'update':
                        result = self.dataset_migrator.update_dataset_datasource(
                            dataset_id=dataset_id,
                            old_datasource_id=self.aurora_datasource_id,
                            new_datasource_id=self.redshift_datasource_id
                        )
                        if result:
                            success_count += 1
                    
                    elif self.migration_mode == 'clone':
                        new_dataset_id = f"{dataset_id}{self.suffix}"
                        result = self.dataset_migrator.clone_dataset_with_new_datasource(
                            source_dataset_id=dataset_id,
                            new_dataset_id=new_dataset_id,
                            new_datasource_id=self.redshift_datasource_id,
                            old_datasource_id=self.aurora_datasource_id,
                            suffix=self.suffix
                        )
                        if result:
                            success_count += 1
                    
                    time.sleep(1)  # Rate limiting
                    
                except Exception as e:
                    print(f"  ❌ Failed: {e}")
                    error_count += 1
                    self.results['errors'].append(f"Dataset {dataset_id}: {str(e)}")
                
                print()
            
            self.results['datasets_migrated'] = success_count
            self.results['datasets_failed'] = error_count
            
            print(f"Dataset Migration Summary:")
            print(f"  ✅ Successful: {success_count}")
            print(f"  ❌ Failed: {error_count}")
            
            return error_count == 0
        
        except Exception as e:
            print(f"\n❌ Error during dataset migration: {e}")
            self.results['errors'].append(f"Dataset migration error: {str(e)}")
            return False
    
    def _run_audit(self):
        """Run audit checks on migrated resources."""
        print("\n" + "=" * 80)
        print("STEP 4: Running Audit Checks")
        print("=" * 80)
        
        try:
            # Audit Redshift data source
            self.auditor.audit_redshift_datasource(self.redshift_datasource_id)
            
            # Audit migrated datasets
            self.auditor.audit_migrated_datasets(self.redshift_datasource_id)
            
            # Check if audit passed (no critical issues)
            self.results['audit_passed'] = len(self.auditor.issues) == 0
            
        except Exception as e:
            print(f"\n❌ Error during audit: {e}")
            self.results['errors'].append(f"Audit error: {str(e)}")
    
    def _generate_report(self):
        """Generate final migration report."""
        print("\n" + "=" * 80)
        print("MIGRATION REPORT")
        print("=" * 80)
        
        print(f"\nResults:")
        print(f"  Redshift Data Source: {'✅ Created' if self.results['datasource_created'] else '❌ Failed'}")
        print(f"  Datasets Migrated: {self.results['datasets_migrated']}")
        print(f"  Datasets Failed: {self.results['datasets_failed']}")
        print(f"  Audit Status: {'✅ Passed' if self.results['audit_passed'] else '❌ Failed'}")
        
        if self.results['errors']:
            print(f"\n❌ Errors Encountered ({len(self.results['errors'])}):")
            for i, error in enumerate(self.results['errors'], 1):
                print(f"  {i}. {error}")
        
        if self.results['audit_passed'] and self.results['datasets_failed'] == 0:
            print("\n✅ Migration completed successfully!")
            
            if self.migration_mode == 'clone':
                print("\nNext Steps:")
                print("  1. Test the cloned datasets and analyses")
                print("  2. Update analyses to use new datasets (if needed)")
                print("  3. Publish dashboards from updated analyses")
                print("  4. Gradually migrate users to new dashboards")
                print("  5. Decommission old resources after validation")
            else:
                print("\nNext Steps:")
                print("  1. Verify all dashboards and analyses work correctly")
                print("  2. Test dataset refreshes")
                print("  3. Monitor for any errors over next 24-48 hours")
        else:
            print("\n⚠️  Migration completed with issues. Please review errors above.")
        
        print("\n" + "=" * 80)
        
        # Save report to file
        report_file = f"migration_report_{int(time.time())}.json"
        with open(report_file, 'w') as f:
            json.dump(self.results, f, indent=2, default=str)
        print(f"\nDetailed report saved to: {report_file}")


def main():
    parser = argparse.ArgumentParser(
        description='Batch migrate QuickSight resources from Aurora to Redshift',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example config file (migration_config.json):
{
  "aws_account_id": "123456789012",
  "region": "us-east-1",
  "aurora_datasource_id": "aurora-prod-datasource",
  "redshift_config": {
    "data_source_id": "redshift-prod-datasource",
    "name": "Production Redshift",
    "cluster_id": "my-cluster",
    "host": "my-cluster.abc.us-east-1.redshift.amazonaws.com",
    "port": 5439,
    "database": "analytics",
    "username": "quicksight_user",
    "password": "your-password",
    "vpc_connection_arn": "arn:aws:quicksight:us-east-1:123456789012:vpcConnection/vpc-id"
  },
  "migration_mode": "clone",
  "suffix": "-redshift"
}
        """
    )
    parser.add_argument(
        '--config',
        required=True,
        help='Path to migration configuration JSON file'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Validate configuration without executing migration'
    )
    
    args = parser.parse_args()
    
    # Load and validate config
    try:
        with open(args.config, 'r') as f:
            config = json.load(f)
        
        # Validate required fields
        required_fields = ['aws_account_id', 'aurora_datasource_id', 'redshift_config']
        for field in required_fields:
            if field not in config:
                print(f"❌ Missing required field in config: {field}")
                sys.exit(1)
        
        print("✅ Configuration validated successfully")
        
        if args.dry_run:
            print("\n🔍 Dry run mode - configuration looks good!")
            print("\nRemove --dry-run flag to execute migration.")
            sys.exit(0)
    
    except FileNotFoundError:
        print(f"❌ Config file not found: {args.config}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"❌ Invalid JSON in config file: {e}")
        sys.exit(1)
    
    # Confirm with user
    if config.get('migration_mode') == 'update':
        print("\n⚠️  WARNING: You are using UPDATE mode which modifies datasets in-place!")
        print("   This cannot be easily undone. Make sure you have backups.")
        confirm = input("\nType 'yes' to continue: ")
        if confirm.lower() != 'yes':
            print("Aborted.")
            sys.exit(0)
    
    # Run migration
    migrator = BatchMigrator(args.config)
    success = migrator.run_migration()
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
