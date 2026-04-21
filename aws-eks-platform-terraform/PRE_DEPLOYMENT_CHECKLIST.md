# Pre-Deployment Checklist

## Before Running `./scripts/bootstrap.sh`

### 1. AWS Setup
- [ ] AWS CLI configured with AdministratorAccess
- [ ] Run: `aws sts get-caller-identity` (should show account 288528696055)
- [ ] Region: us-east-1

### 2. GitHub Setup
- [ ] Repository pushed to: https://github.com/Ea-mjolnir/aws-eks-platform-terraform
- [ ] GitHub Personal Access Token created (repo scope)
- [ ] Update argocd/install/argocd-install.yaml with token

### 3. Domain Setup (Optional)
- [ ] If using custom domain, update ingress hosts
- [ ] Or use nip.io for testing (automatic)

### 4. ECR Repository
- [ ] Create ECR repo: `aws ecr create-repository --repository-name eks-platform/task-api`

### 5. Secrets Manager (Optional for first deploy)
- [ ] Create secrets in AWS Secrets Manager (see manifests/external-secrets.yaml)

## Expected Deployment Time
- VPC + Subnets: 3-4 minutes
- EKS Cluster: 10-12 minutes
- Node Groups: 3-4 minutes
- Addons: 5-7 minutes
- ArgoCD Sync: 2-3 minutes
- **Total: ~25-30 minutes**

## Post-Deployment Verification
- [ ] `kubectl get nodes` shows 4+ nodes
- [ ] `kubectl get pods -A` shows all pods running
- [ ] ArgoCD UI accessible via port-forward
- [ ] Task API health check passes

## Rollback Plan
If deployment fails:
1. `terraform destroy -auto-approve` (cleans up all AWS resources)
2. Fix issue
3. Re-run `./scripts/bootstrap.sh`
