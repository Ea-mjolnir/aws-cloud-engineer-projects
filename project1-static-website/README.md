# AWS Static Website + CloudFront CDN
**Status:** Live | **Cost:** <$1/month | **IaC:** 100% Terraform
## Architecture
S3 (private) → CloudFront OAC → 400+ edge locations → User
## What this demonstrates
- Infrastructure as Code (Terraform) — zero manual AWS console clicks
- Security by default — private S3, OAC, forced HTTPS
- Cost-optimized CDN with PriceClass_100
- Well-Architected Framework review
## Tech stack
AWS S3 · AWS CloudFront · Terraform
## Deployment
```bash
terraform init && terraform apply

