# AWS Serverless Task Management API

A production-grade serverless task management API built with AWS services and deployed via Terraform.

## Architecture Overview

Client → WAF → API Gateway → Cognito Authorizer → Lambda (CRUD)
↓
DynamoDB (Single Table + GSI)
SQS → Lambda (Async) → DLQ
S3 (Presigned URLs for attachments)
X-Ray (Distributed Tracing)
CloudWatch (Logs + Alarms)

## Features

- ✅ **Authentication**: Cognito User Pool with MFA and advanced security
- ✅ **Authorization**: JWT validation via API Gateway authorizer
- ✅ **CRUD Operations**: Create, read, update, delete tasks
- ✅ **Async Processing**: SQS queue for notifications with Dead Letter Queue
- ✅ **File Attachments**: Presigned S3 URLs for direct uploads
- ✅ **Security**: WAF with rate limiting, SQL injection protection, AWS managed rules
- ✅ **Observability**: CloudWatch logs, metrics, alarms + X-Ray tracing
- ✅ **Single-Table Design**: DynamoDB optimized for access patterns
- ✅ **Infrastructure as Code**: Complete Terraform configuration

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.7
- Python 3.12 (for local Lambda development)
- jq (for JSON formatting in test scripts)

## Quick Start

### 1. Clone and Initialize

```bash
git clone <your-repo>
cd aws-serverless-api-terraform
terraform init
terraform apply -auto-approve
chmod +x test-api.sh
./test-api.sh
curl -X POST "$(terraform output -raw api_endpoint)/tasks" \
  -H "Authorization: $(aws cognito-idp admin-initiate-auth --user-pool-id $(terraform output -raw cognito_user_pool_id) --client-id $(terraform output -raw cognito_client_id) --auth-flow ADMIN_USER_PASSWORD_AUTH --auth-parameters 'USERNAME=testuser@example.com,PASSWORD=Temp123!@#ABC' --query 'AuthenticationResult.IdToken' --output text)" \
  -H "Content-Type: application/json" \
  -d '{"title": "Learn AWS", "priority": "HIGH"}'
./test-api.sh
├── providers.tf          # AWS provider configuration
├── versions.tf           # Terraform version constraints
├── variables.tf          # Input variables
├── cognito.tf            # Cognito User Pool + Client
├── dynamodb.tf           # DynamoDB single-table design
├── s3.tf                 # S3 bucket for attachments
├── sqs.tf                # SQS queue + DLQ + alarms
├── iam.tf                # IAM roles and policies
├── lambda.tf             # Lambda functions + event source mapping
├── api_gateway.tf        # API Gateway + authorizer + routes
├── waf.tf                # WAF web ACL + rules
├── cloudwatch.tf         # Log groups + metrics + alarms
├── outputs.tf            # Output values
├── lambda/
│   ├── tasks_crud/       # CRUD Lambda handler
│   └── tasks_notification/ # SQS consumer Lambda
├── test-api.sh           # API test script
├── reset-user.sh         # Reset Cognito user script
├── WELL_ARCHITECTED_REVIEW.md
└── README.md

