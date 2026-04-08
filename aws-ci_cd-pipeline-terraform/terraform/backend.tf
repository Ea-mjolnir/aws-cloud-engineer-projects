# Remote state in S3 — critical for team collaboration and pipeline use
# Create this bucket MANUALLY before running terraform init:
# aws s3 mb s3://aws-ci-cd-pipeline-terraform-state
# aws s3api put-bucket-versioning --bucket aws-ci-cd-pipeline-terraform-state --versioning-configuration Status=Enabled
# aws dynamodb create-table --table-name terraform-locks \
#   --attribute-definitions AttributeName=LockID,AttributeType=S \
#   --key-schema AttributeName=LockID,KeyType=HASH \
#   --billing-mode PAY_PER_REQUEST

terraform {
  backend "s3" {
    bucket         = "aws-ci-cd-pipeline-terraform-state"
    key            = "cicd-pipeline/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
