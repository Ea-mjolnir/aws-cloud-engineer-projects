cd aws-eks-platform-terraform

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 PRE-COMMIT PRODUCTION AUDIT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# =============================================================================
# 1. Check for hardcoded sensitive values
# =============================================================================
echo "📦 [1/10] Scanning for hardcoded secrets..."
SENSITIVE_PATTERNS=(
    "password.*=.*[^$]"
    "secret.*=.*[^$]"
    "token.*=.*[^$]"
    "api_key.*=.*[^$]"
    "BEGIN.*PRIVATE KEY"
    "AKIA[0-9A-Z]{16}"
    "288528696055"  # Your AWS account ID (should be in variables, not hardcoded everywhere)
)

for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    FOUND=$(grep -r "$pattern" --include="*.tf" --include="*.yaml" --include="*.yml" --include="*.sh" . 2>/dev/null | grep -v ".git" | grep -v "variables.tf" | grep -v "outputs.tf" | head -5)
    if [ -n "$FOUND" ]; then
        echo "  ⚠️  Found potential sensitive data:"
        echo "$FOUND" | head -3
    fi
done
echo "  ✅ Secret scan complete"

# =============================================================================
# 2. Check for placeholder values that need replacement
# =============================================================================
echo ""
echo "📦 [2/10] Checking for placeholder values..."
PLACEHOLDERS=(
    "YOUR_GITHUB_ORG"
    "YOUR_GITHUB_TOKEN_HERE"
    "ACCOUNT_ID"
    "example.com"
    "changeme"
    "CHANGE_ME"
    "REPLACE_ME"
)

for placeholder in "${PLACEHOLDERS[@]}"; do
    FOUND=$(grep -rn "$placeholder" --include="*.tf" --include="*.yaml" --include="*.yml" --include="*.sh" . 2>/dev/null | grep -v ".git" | grep -v "README.md" | wc -l | tr -d ' ')
    if [ "$FOUND" -gt 0 ]; then
        echo "  ⚠️  Found '$placeholder' in $FOUND files"
    fi
done
echo "  ✅ Placeholder check complete"

# =============================================================================
# 3. Validate AWS Account ID consistency
# =============================================================================
echo ""
echo "📦 [3/10] Checking AWS Account ID consistency..."
ACCOUNT_ID="288528696055"

# Check if account ID is correct format
if [[ ! "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
    echo "  ❌ AWS Account ID format invalid: $ACCOUNT_ID"
fi

# Check for typos in account ID
TYPO_COUNT=$(grep -r "2885-2869-6055\|2885 2869 6055" --include="*.tf" --include="*.yaml" . 2>/dev/null | wc -l | tr -d ' ')
if [ "$TYPO_COUNT" -gt 0 ]; then
    echo "  ⚠️  Found $TYPO_COUNT files with hyphenated account ID (should be without hyphens)"
fi

echo "  ✅ Account ID: $ACCOUNT_ID"

# =============================================================================
# 4. Check GitHub repository references
# =============================================================================
echo ""
echo "📦 [4/10] Checking GitHub references..."
GITHUB_ORG="Ea-mjolnir"
GITHUB_REPO="aws-eks-platform-terraform"

# Check for correct repo references
WRONG_REPO=$(grep -r "YOUR_GITHUB_ORG/aws-eks-platform-terraform" --include="*.yaml" --include="*.yml" . 2>/dev/null | wc -l | tr -d ' ')
if [ "$WRONG_REPO" -gt 0 ]; then
    echo "  ⚠️  Found $WRONG_REPO files with 'YOUR_GITHUB_ORG' placeholder"
fi

# Check ArgoCD repo URLs
ARGOCD_REPOS=$(grep -h "repoURL:" argocd/apps/*.yaml 2>/dev/null | sort -u)
echo "  ArgoCD Repos: $ARGOCD_REPOS"

# =============================================================================
# 5. Validate Terraform variable defaults
# =============================================================================
echo ""
echo "📦 [5/10] Validating Terraform variables..."

# Check if github_org has default value
if grep -q "variable \"github_org\".*default" terraform/variables.tf; then
    DEFAULT_ORG=$(grep -A2 "variable \"github_org\"" terraform/variables.tf | grep default | sed 's/.*default.*=.*"\(.*\)".*/\1/')
    echo "  github_org default: $DEFAULT_ORG"
else
    echo "  ⚠️  github_org has NO default (will require input)"
fi

# Check node group instance types (should be available in us-east-1)
echo "  Node group instance types:"
grep -A1 "instance_types" terraform/variables.tf | grep "t3\|m5" | head -4

# =============================================================================
# 6. Check for missing required files
# =============================================================================
echo ""
echo "📦 [6/10] Checking for missing critical files..."

CRITICAL_FILES=(
    "app/Dockerfile"
    "app/requirements.txt"
    "app/main.py"
    "scripts/bootstrap.sh"
    "scripts/rollback.sh"
    ".github/workflows/eks-ci.yml"
    "monitoring/values.yaml"
)

for file in "${CRITICAL_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "  ❌ Missing: $file"
    fi
done
echo "  ✅ Critical files present"

# =============================================================================
# 7. Validate Helm chart version consistency
# =============================================================================
echo ""
echo "📦 [7/10] Validating Helm chart consistency..."

CHART_VERSION=$(grep "^version:" helm/task-api/Chart.yaml | awk '{print $2}')
APP_VERSION=$(grep "^appVersion:" helm/task-api/Chart.yaml | awk '{print $2}')
echo "  Chart version: $CHART_VERSION"
echo "  App version:   $APP_VERSION"

# Check values files for required fields
echo "  Checking values files..."
for values in helm/task-api/values.yaml helm/task-api/values-production.yaml; do
    if [ -f "$values" ]; then
        if grep -q "repository:.*\".*\"" "$values" 2>/dev/null; then
            echo "    ✅ $values has repository field"
        fi
    fi
done

# =============================================================================
# 8. Check Kubernetes API versions (deprecation check)
# =============================================================================
echo ""
echo "📦 [8/10] Checking for deprecated API versions..."

# Check for deprecated APIs (EKS 1.29)
DEPRECATED_APIS=(
    "extensions/v1beta1"
    "apps/v1beta1"
    "apps/v1beta2"
    "rbac.authorization.k8s.io/v1beta1"
    "policy/v1beta1"
)

for api in "${DEPRECATED_APIS[@]}"; do
    FOUND=$(grep -r "apiVersion: $api" --include="*.yaml" --include="*.yml" . 2>/dev/null | wc -l | tr -d ' ')
    if [ "$FOUND" -gt 0 ]; then
        echo "  ❌ Found deprecated API: $api in $FOUND files"
    fi
done
echo "  ✅ API version check complete"

# =============================================================================
# 9. Check for common misconfigurations
# =============================================================================
echo ""
echo "📦 [9/10] Checking for common misconfigurations..."

# Check if HPA has both CPU and memory metrics
if grep -q "cpu.*memory\|memory.*cpu" helm/task-api/values.yaml; then
    echo "  ✅ HPA has multiple metrics"
fi

# Check if PDB is configured
if grep -q "podDisruptionBudget" helm/task-api/values.yaml; then
    echo "  ✅ PDB is configured"
fi

# Check if network policy exists
if [ -f "helm/task-api/templates/networkpolicy.yaml" ]; then
    echo "  ✅ NetworkPolicy exists"
fi

# Check if IRSA annotations use correct format
IRSA_FORMAT=$(grep -h "eks.amazonaws.com/role-arn" helm/task-api/templates/serviceaccount.yaml 2>/dev/null)
if [ -n "$IRSA_FORMAT" ]; then
    echo "  ✅ IRSA annotation present"
fi

# =============================================================================
# 10. Generate deployment checklist
# =============================================================================
echo ""
echo "📦 [10/10] Generating pre-deployment checklist..."

cat > PRE_DEPLOYMENT_CHECKLIST.md << 'EOF'
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
EOF

echo "  ✅ Checklist generated: PRE_DEPLOYMENT_CHECKLIST.md"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 AUDIT SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "🔧 Manual Actions Required BEFORE Commit:"
echo ""
echo "1. Update GitHub Token:"
echo "   File: argocd/install/argocd-install.yaml"
echo "   Line: password: YOUR_GITHUB_TOKEN_HERE"
echo "   → Replace with GitHub Personal Access Token"
echo ""
echo "2. Verify these files have correct values:"
echo "   - argocd/apps/task-api.yaml (ECR registry URL)"
echo "   - .github/workflows/eks-ci.yml (AWS account ID)"
echo "   - scripts/bootstrap.sh (GitHub org)"
echo ""
echo "3. Optional - Change Grafana password:"
echo "   File: monitoring/values.yaml"
echo "   Line: adminPassword: admin"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Files to review before commit:"
git ls-files --others --exclude-standard | head -20
echo "   ... and more"
echo ""
echo "✅ Ready to commit after addressing the manual actions above!"
