#!/bin/bash

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 FINAL PRE-COMMIT VALIDATION SUITE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PASSED_ALL=true
SUB_PATH="aws-eks-platform-terraform"
MAIN_REPO="aws-cloud-engineer-projects"
EXPECTED_ACCOUNT="288528696055"

# =============================================================================
# TEST 1: Critical Files
# =============================================================================
echo "📄 [TEST 1/6] Checking critical files..."

CRITICAL_FILES=(
    "terraform/backend.tf"
    "terraform/providers.tf"
    "terraform/variables.tf"
    "terraform/vpc.tf"
    "terraform/eks.tf"
    "terraform/irsa.tf"
    "terraform/addons.tf"
    "terraform/outputs.tf"
    "helm/task-api/Chart.yaml"
    "helm/task-api/values.yaml"
    "helm/task-api/values-production.yaml"
    "argocd/projects/platform.yaml"
    "argocd/apps/app-of-apps.yaml"
    "argocd/apps/task-api.yaml"
    "manifests/namespaces.yaml"
    "manifests/rbac.yaml"
    "manifests/external-secrets.yaml"
    "app/Dockerfile"
    "app/main.py"
    "app/requirements.txt"
    "scripts/bootstrap.sh"
    ".github/workflows/eks-ci.yml"
    "monitoring/values.yaml"
)

FILE_PASS=0
for file in "${CRITICAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        ((FILE_PASS++))
    else
        echo "  ❌ $file - MISSING"
        PASSED_ALL=false
    fi
done
echo "  ✅ $FILE_PASS/${#CRITICAL_FILES[@]} critical files present"
echo ""

# =============================================================================
# TEST 2: Terraform Validation
# =============================================================================
echo "🔧 [TEST 2/6] Validating Terraform..."

cd terraform
rm -rf .terraform .terraform.lock.hcl 2>/dev/null || true

if terraform init -backend=false > /dev/null 2>&1; then
    if terraform validate > /dev/null 2>&1; then
        echo "  ✅ Terraform configuration is valid"
    else
        echo "  ❌ Terraform validation failed"
        PASSED_ALL=false
    fi
else
    echo "  ❌ Terraform init failed"
    PASSED_ALL=false
fi
cd ..
echo ""

# =============================================================================
# TEST 3: Helm Validation
# =============================================================================
echo "⎈ [TEST 3/6] Validating Helm charts..."

if helm lint helm/task-api/ > /dev/null 2>&1; then
    TEMPLATE_OUTPUT=$(helm template test helm/task-api/ \
        --namespace production \
        --values helm/task-api/values.yaml \
        --values helm/task-api/values-production.yaml \
        --set image.repository="test.dkr.ecr.us-east-1.amazonaws.com/task-api" \
        --set image.tag="latest" 2>&1)
    
    if [ $? -eq 0 ]; then
        DEPLOYMENTS=$(echo "$TEMPLATE_OUTPUT" | grep -c "kind: Deployment" || echo 0)
        SERVICES=$(echo "$TEMPLATE_OUTPUT" | grep -c "kind: Service" || echo 0)
        HPA=$(echo "$TEMPLATE_OUTPUT" | grep -c "kind: HorizontalPodAutoscaler" || echo 0)
        echo "  ✅ Helm chart renders ($DEPLOYMENTS deployments, $SERVICES services, $HPA HPA)"
    else
        echo "  ❌ Helm template rendering failed"
        PASSED_ALL=false
    fi
else
    echo "  ❌ Helm lint failed"
    PASSED_ALL=false
fi
echo ""

# =============================================================================
# TEST 4: Monorepo Configuration
# =============================================================================
echo "📦 [TEST 4/6] Checking monorepo configuration..."

if grep -q "path: ${SUB_PATH}/argocd/apps" argocd/apps/app-of-apps.yaml; then
    echo "  ✅ app-of-apps path correct"
else
    echo "  ❌ app-of-apps path incorrect"
    PASSED_ALL=false
fi

if grep -q "path: ${SUB_PATH}/helm/task-api" argocd/apps/task-api.yaml; then
    echo "  ✅ task-api path correct"
else
    echo "  ❌ task-api path incorrect"
    PASSED_ALL=false
fi

if grep -q "github.com/Ea-mjolnir/${MAIN_REPO}" argocd/projects/platform.yaml; then
    echo "  ✅ Repository URL correct"
else
    echo "  ❌ Repository URL incorrect"
    PASSED_ALL=false
fi

if grep -q "working-directory" .github/workflows/eks-ci.yml; then
    echo "  ✅ GitHub Actions uses working-directory"
else
    echo "  ⚠️  GitHub Actions may need working-directory"
fi
echo ""

# =============================================================================
# TEST 5: Placeholders & Values
# =============================================================================
echo "🔐 [TEST 5/6] Checking for placeholders..."

PLACEHOLDERS=$(grep -r "YOUR_GITHUB_TOKEN_HERE\|changeme\|CHANGE_ME" --include="*.yaml" --include="*.yml" . 2>/dev/null | grep -v ".git" | grep -v "README" | grep -v "env.example" | grep -v "GITHUB_TOKEN_SETUP" | wc -l | tr -d ' ')

if [ "$PLACEHOLDERS" -eq 0 ]; then
    echo "  ✅ No unresolved placeholders"
else
    echo "  ⚠️  Found $PLACEHOLDERS placeholders (GitHub token needs manual setup)"
fi

ACCOUNT_COUNT=$(grep -r "$EXPECTED_ACCOUNT" --include="*.yaml" --include="*.yml" . 2>/dev/null | wc -l | tr -d ' ')
echo "  ✅ Account ID $EXPECTED_ACCOUNT found in $ACCOUNT_COUNT files"

if grep -q "0.0.0.0/0" terraform/variables.tf; then
    echo "  ✅ Learning mode: API endpoint open (0.0.0.0/0)"
fi
echo ""

# =============================================================================
# TEST 6: Shell & Python Syntax
# =============================================================================
echo "🐚 [TEST 6/6] Checking scripts..."

SCRIPT_FAIL=0
for script in scripts/*.sh; do
    if [ -f "$script" ]; then
        if ! bash -n "$script" 2>/dev/null; then
            ((SCRIPT_FAIL++))
        fi
    fi
done

if [ $SCRIPT_FAIL -eq 0 ]; then
    echo "  ✅ All shell scripts syntax OK"
else
    echo "  ❌ $SCRIPT_FAIL shell scripts have syntax errors"
    PASSED_ALL=false
fi

if python3 -m py_compile app/main.py 2>/dev/null; then
    echo "  ✅ Python syntax OK"
else
    echo "  ❌ Python syntax error"
    PASSED_ALL=false
fi
echo ""

# =============================================================================
# Statistics
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 PROJECT STATISTICS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Terraform:  $(find terraform -name "*.tf" -type f 2>/dev/null | wc -l) files"
echo "  Helm:       $(find helm -name "*.yaml" -type f 2>/dev/null | wc -l) files"
echo "  Manifests:  $(find manifests -name "*.yaml" -type f 2>/dev/null | wc -l) files"
echo "  ArgoCD:     $(find argocd -name "*.yaml" -type f 2>/dev/null | wc -l) files"
echo "  Scripts:    $(find scripts -name "*.sh" -type f 2>/dev/null | wc -l) files"
echo ""

# =============================================================================
# FINAL VERDICT
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 FINAL VERDICT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$PASSED_ALL" = true ]; then
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    ✅ ALL CHECKS PASSED!                                    ║"
    echo "║                    🚀 READY TO COMMIT AND DEPLOY                           ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Commit from: ~/aws-cloud-engineer-projects"
    echo ""
    echo "  cd ~/aws-cloud-engineer-projects"
    echo "  git status"
    echo "  git add aws-eks-platform-terraform/"
    echo "  git commit -m 'feat: Complete production EKS platform with GitOps'"
    echo "  git push origin master"
    echo ""
    echo "After push, deploy with:"
    echo "  cd aws-eks-platform-terraform"
    echo "  ./scripts/bootstrap.sh"
else
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    ❌ SOME CHECKS FAILED                                    ║"
    echo "║                    REVIEW ISSUES ABOVE                                      ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
fi
echo ""
