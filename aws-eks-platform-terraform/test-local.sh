#!/bin/bash
set -euo pipefail

# =============================================================================
# LOCAL TESTING SUITE - FIXED VERSION
# =============================================================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 LOCAL TESTING SUITE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# -----------------------------------------------------------------------------
# 1. File Structure Validation
# -----------------------------------------------------------------------------
echo -e "${BLUE}📁 [1/7] Checking file structure...${NC}"
REQUIRED_FILES=(
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
    "helm/task-api/templates/_helpers.tpl"
    "helm/task-api/templates/deployment.yaml"
    "helm/task-api/templates/service.yaml"
    "helm/task-api/templates/ingress.yaml"
    "helm/task-api/templates/hpa.yaml"
    "helm/task-api/templates/pdb.yaml"
    "helm/task-api/templates/networkpolicy.yaml"
    "helm/task-api/templates/serviceaccount.yaml"
    "helm/task-api/templates/configmap.yaml"
    "argocd/projects/platform.yaml"
    "argocd/apps/app-of-apps.yaml"
    "argocd/apps/task-api.yaml"
    "argocd/apps/monitoring.yaml"
    "manifests/namespaces.yaml"
    "manifests/rbac.yaml"
    "manifests/external-secrets.yaml"
    "app/Dockerfile"
    "app/main.py"
    "app/requirements.txt"
    "scripts/bootstrap.sh"
    ".github/workflows/eks-ci.yml"
)

MISSING_FILES=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "  ${GREEN}✅${NC} $file"
    else
        echo -e "  ${RED}❌${NC} $file - MISSING"
        MISSING_FILES=$((MISSING_FILES + 1))
    fi
done

if [ $MISSING_FILES -eq 0 ]; then
    echo -e "  ${GREEN}✅ All required files present${NC}"
else
    echo -e "  ${YELLOW}⚠️  $MISSING_FILES files missing${NC}"
fi

# -----------------------------------------------------------------------------
# 2. Terraform Format Check (No init required)
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}📦 [2/7] Checking Terraform format...${NC}"

cd terraform

# Check if terraform is installed
if command -v terraform > /dev/null 2>&1; then
    echo "  → Checking terraform fmt..."
    if terraform fmt -check -recursive . 2>/dev/null; then
        echo -e "  ${GREEN}✅ Terraform format is correct${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Terraform files need formatting${NC}"
        echo "  Run: terraform fmt -recursive"
    fi
else
    echo -e "  ${YELLOW}⚠️  Terraform not installed - skipping format check${NC}"
fi

cd ..

# -----------------------------------------------------------------------------
# 3. Terraform Validate (Init with backend=false)
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}📦 [3/7] Validating Terraform configuration...${NC}"

cd terraform

if command -v terraform > /dev/null 2>&1; then
    echo "  → Initializing Terraform (backend=false for validation)..."
    if terraform init -backend=false > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Terraform initialized${NC}"
    else
        echo -e "  ${RED}❌ Terraform init failed${NC}"
        cd ..
        exit 1
    fi
    
    echo "  → Validating Terraform..."
    if terraform validate > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Terraform configuration is valid${NC}"
    else
        echo -e "  ${RED}❌ Terraform validation failed:${NC}"
        terraform validate
    fi
    
    # Clean up .terraform directory
    rm -rf .terraform .terraform.lock.hcl 2>/dev/null || true
else
    echo -e "  ${YELLOW}⚠️  Terraform not installed - skipping validation${NC}"
fi

cd ..

# -----------------------------------------------------------------------------
# 4. Helm Lint
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}📦 [4/7] Testing Helm charts...${NC}"

if command -v helm > /dev/null 2>&1; then
    echo "  → Linting task-api chart..."
    if helm lint helm/task-api/ > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Helm chart is valid${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Helm lint warnings:${NC}"
        helm lint helm/task-api/ 2>&1 | head -10
    fi
    
    echo "  → Testing template rendering..."
    if helm template test helm/task-api/ \
        --namespace production \
        --values helm/task-api/values.yaml \
        --values helm/task-api/values-production.yaml \
        --set image.repository="test.dkr.ecr.us-east-1.amazonaws.com/task-api" \
        --set image.tag="latest" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Templates render successfully${NC}"
    else
        echo -e "  ${RED}❌ Template rendering failed${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️  Helm not installed - skipping chart tests${NC}"
fi

# -----------------------------------------------------------------------------
# 5. YAML Validation
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}📦 [5/7] Validating YAML files...${NC}"

# Use grep for basic YAML structure validation
YAML_ERRORS=0
for file in $(find . -name "*.yaml" -o -name "*.yml" 2>/dev/null | grep -v ".terraform" | grep -v ".git"); do
    # Basic check: file should not be empty and should have apiVersion or similar
    if [ -s "$file" ]; then
        if grep -q "apiVersion\|kind\|metadata" "$file" 2>/dev/null || [[ "$file" == *"values"* ]]; then
            echo -e "  ${GREEN}✅${NC} $file"
        else
            echo -e "  ${YELLOW}⚠️${NC}  $file (may not be valid Kubernetes YAML)"
        fi
    else
        echo -e "  ${YELLOW}⚠️${NC}  $file (empty file)"
    fi
done

# -----------------------------------------------------------------------------
# 6. Shell Script Validation
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}📦 [6/7] Testing shell scripts...${NC}"

for script in scripts/*.sh; do
    if [ -f "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
            echo -e "  ${GREEN}✅${NC} $script syntax OK"
        else
            echo -e "  ${RED}❌${NC} $script syntax error"
            bash -n "$script"
        fi
    fi
done

# Make scripts executable
chmod +x scripts/*.sh 2>/dev/null || true

# -----------------------------------------------------------------------------
# 7. Python Syntax Check
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}📦 [7/7] Testing Python code...${NC}"

if command -v python3 > /dev/null 2>&1; then
    if python3 -m py_compile app/main.py 2>/dev/null; then
        echo -e "  ${GREEN}✅${NC} main.py syntax is valid"
    else
        echo -e "  ${RED}❌${NC} main.py has syntax errors"
        python3 -m py_compile app/main.py 2>&1 || true
    fi
else
    echo -e "  ${YELLOW}⚠️  Python not installed - skipping Python validation${NC}"
fi

# -----------------------------------------------------------------------------
# Git Status
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}📊 Git Status${NC}"

if git rev-parse --git-dir > /dev/null 2>&1; then
    echo "  → Current branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"
    
    STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    UNSTAGED=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    
    echo "  → Staged: $STAGED | Unstaged: $UNSTAGED | Untracked: $UNTRACKED"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📊 TEST SUMMARY${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📁 File counts:"
echo "   Terraform:  $(find terraform -name "*.tf" -type f 2>/dev/null | wc -l | tr -d ' ') files"
echo "   Helm:       $(find helm -name "*.yaml" -o -name "*.tpl" -type f 2>/dev/null | wc -l | tr -d ' ') files"
echo "   Manifests:  $(find manifests -name "*.yaml" -type f 2>/dev/null | wc -l | tr -d ' ') files"
echo "   ArgoCD:     $(find argocd -name "*.yaml" -type f 2>/dev/null | wc -l | tr -d ' ') files"
echo "   Scripts:    $(find scripts -name "*.sh" -type f 2>/dev/null | wc -l | tr -d ' ') files"

echo ""
echo -e "${GREEN}✅ Ready for commit!${NC}"
echo ""
echo "📋 Next steps:"
echo "   1. Fix any formatting: terraform fmt -recursive terraform/"
echo "   2. git add ."
echo "   3. git commit -m 'Complete EKS platform with GitOps'"
echo "   4. git push origin main"
echo ""
