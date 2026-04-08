# AWS 3-Tier Web Application

**Status:** Deployable | **Cost:** Free Tier eligible | **IaC:** 100% Terraform

## Architecture

## What this demonstrates
- Production-grade VPC with public, private, and isolated subnets across 2 AZs
- Auto-scaling EC2 instances behind Application Load Balancer
- Security group isolation between tiers
- RDS database with automated backups
- CloudWatch monitoring + auto-scaling alarms

## Tech Stack
- AWS VPC · ALB · EC2 Auto Scaling · RDS MySQL
- Terraform · CloudWatch · NAT Gateway

## Deployment
```bash
export TF_VAR_db_password="YourSecurePassword123!"
terraform init
terraform apply
# Get application URL
terraform output application_url

# Test load balancing
for i in {1..6}; do curl -s $(terraform output -raw alb_dns_name) | grep "Instance ID"; done

EOF 

