# terraform/backend.tf
terraform {
  backend "s3" {
    # Use variables for multi-environment support
    bucket = "eks-platform-tfstate-${data.aws_caller_identity.current.account_id}"
    key    = "${var.environment}/${var.cluster_name}/terraform.tfstate"
    region = var.aws_region

    encrypt        = true
    dynamodb_table = "terraform-locks-${var.environment}"

    # Additional safety features
    acl              = "private"
    force_path_style = false

    # Enable versioning via bucket configuration (separate resource)
    # This allows rolling back to previous state versions
  }
}

# We'll also create the bucket in a separate bootstrap process
# Create this as scripts/create-tfstate-bucket.sh
