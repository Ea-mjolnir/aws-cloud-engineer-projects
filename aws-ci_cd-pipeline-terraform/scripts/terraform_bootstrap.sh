#!/bin/bash
# This script handles the first-run chicken-and-egg problem
# It only runs special logic if the state bucket doesn't exist yet

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

cd "$TERRAFORM_DIR"

BUCKET="aws-ci-cd-pipeline-terraform-state"
REGION="us-east-1"

echo "Checking if state bucket exists..."
echo "Working directory: $(pwd)"

if aws s3 ls "s3://$BUCKET" --region $REGION 2>/dev/null; then
    echo "✅ State bucket exists. Running normal Terraform."
    terraform init
    terraform apply -auto-approve
else
    echo "⚠️  State bucket does NOT exist. Running bootstrap workflow..."
    
    # Step 1: Temporarily remove backend.tf (so Terraform uses local state)
    echo "Step 1: Temporarily disabling remote backend..."
    if [ -f backend.tf ]; then
        mv backend.tf backend.tf.bootstrap-bak
        echo "   backend.tf backed up to backend.tf.bootstrap-bak"
    fi
    
    # Step 2: Initialize with LOCAL state
    echo "Step 2: Initializing with local state..."
    terraform init
    
    # Step 3: Apply ONLY the state resources (bucket + DynamoDB)
    echo "Step 3: Creating state resources (S3 bucket + DynamoDB)..."
    terraform apply -auto-approve \
        -target=aws_s3_bucket.terraform_state \
        -target=aws_s3_bucket_versioning.terraform_state \
        -target=aws_s3_bucket_server_side_encryption_configuration.terraform_state \
        -target=aws_s3_bucket_public_access_block.terraform_state \
        -target=aws_dynamodb_table.terraform_locks
    
    # Step 4: Restore backend.tf
    echo "Step 4: Restoring remote backend configuration..."
    if [ -f backend.tf.bootstrap-bak ]; then
        mv backend.tf.bootstrap-bak backend.tf
        echo "   backend.tf restored"
    fi
    
    # Step 5: Migrate local state to remote S3
    echo "Step 5: Migrating state to S3..."
    terraform init -migrate-state -force-copy
    
    # Step 6: Apply remaining resources (ECS, ALB, etc.)
    echo "Step 6: Applying all remaining resources..."
    terraform apply -auto-approve
    
    echo "✅ Bootstrap complete!"
fi
