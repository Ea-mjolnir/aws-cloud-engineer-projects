#!/bin/bash
set -euo pipefail

# =============================================================================
# EKS Platform Bootstrap Script
# =============================================================================
# This script provisions the complete EKS platform from the monorepo structure
# 
# Usage:
#   From project directory:  ./scripts/bootstrap.sh
#   From monorepo root:      WORKING_DIR=aws-eks-platform-terraform ./aws-eks-platform-terraform/scripts/bootstrap.sh
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Determine working directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKING_DIR="${WORKING_DIR:-$PROJECT_DIR}"

# Configuration
GITHUB_ORG="${GITHUB_ORG:-Ea-mjolnir}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-production}"
PROJECT_NAME="eks-platform"
MAIN_REPO="aws-cloud-engineer-projects"
SUB_PATH="aws-eks-platform-terraform"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Install missing tools:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                terraform)
                    echo "  terraform: https://developer.hashicorp.com/terraform/downloads"
                    ;;
                kubectl)
                    echo "  kubectl: https://kubernetes.io/docs/tasks/tools/"
                    ;;
                aws)
                    echo "  aws cli: https://aws.amazon.com/cli/"
                    ;;
                helm)
                    echo "  helm: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
                    ;;
                jq)
                    echo "  jq: sudo apt-get install jq"
                    ;;
            esac
        done
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid"
        echo "Run: aws configure"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log_success "AWS credentials valid (Account: $ACCOUNT_ID)"
    
    # Verify we're in the right directory structure
    if [ ! -d "$PROJECT_DIR/terraform" ]; then
        log_error "Not in the EKS platform directory!"
        echo "Expected to find terraform/ directory in: $PROJECT_DIR"
        echo ""
        echo "If running from monorepo root, use:"
        echo "  WORKING_DIR=$SUB_PATH ./$SUB_PATH/scripts/bootstrap.sh"
        exit 1
    fi
}

# Create Terraform backend bucket if it doesn't exist
create_backend_bucket() {
    local BUCKET_NAME="eks-platform-tfstate-${ACCOUNT_ID}"
    local DYNAMODB_TABLE="terraform-locks-${ENVIRONMENT}"
    
    log_info "Checking Terraform backend..."
    
    if ! aws s3 ls "s3://${BUCKET_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_info "Creating S3 backend bucket: ${BUCKET_NAME}"
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
        aws s3api put-bucket-versioning --bucket "${BUCKET_NAME}" --versioning-configuration Status=Enabled --region "${AWS_REGION}"
        aws s3api put-bucket-encryption --bucket "${BUCKET_NAME}" --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "aws:kms"
                }
            }]
        }' --region "${AWS_REGION}"
        
        # Block public access
        aws s3api put-public-access-block --bucket "${BUCKET_NAME}" --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true --region "${AWS_REGION}"
        
        log_success "S3 backend bucket created"
    else
        log_info "S3 backend bucket already exists"
    fi
    
    if ! aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_info "Creating DynamoDB lock table: ${DYNAMODB_TABLE}"
        aws dynamodb create-table \
            --table-name "${DYNAMODB_TABLE}" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region "${AWS_REGION}"
        
        aws dynamodb wait table-exists --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}"
        log_success "DynamoDB lock table created"
    else
        log_info "DynamoDB lock table already exists"
    fi
}

# Create ECR repository
create_ecr_repo() {
    local REPO_NAME="${PROJECT_NAME}/task-api"
    
    log_info "Checking ECR repository..."
    
    if ! aws ecr describe-repositories --repository-names "${REPO_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_info "Creating ECR repository: ${REPO_NAME}"
        aws ecr create-repository \
            --repository-name "${REPO_NAME}" \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=KMS \
            --region "${AWS_REGION}"
        log_success "ECR repository created"
    else
        log_info "ECR repository already exists"
    fi
}

# Wait for resource to be ready
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local timeout=${4:-300}
    
    log_info "Waiting for ${resource_type}/${resource_name} in ${namespace}..."
    if kubectl wait --for=condition=available --timeout="${timeout}s" -n "${namespace}" "${resource_type}/${resource_name}" 2>/dev/null; then
        log_success "${resource_name} is ready"
    else
        log_warning "Timeout waiting for ${resource_name}. Continuing anyway..."
    fi
}

# Main bootstrap process
main() {
    cd "$PROJECT_DIR"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    🚀 EKS PLATFORM BOOTSTRAP                                ║"
    echo "╠════════════════════════════════════════════════════════════════════════════╣"
    echo "║  GitHub Org:    ${GITHUB_ORG}                                              "
    echo "║  Main Repo:     ${MAIN_REPO}                                               "
    echo "║  Project Path:  ${SUB_PATH}                                                "
    echo "║  AWS Region:    ${AWS_REGION}                                              "
    echo "║  Environment:   ${ENVIRONMENT}                                             "
    echo "║  Account ID:    ${ACCOUNT_ID:-Unknown}                                     "
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    create_backend_bucket
    create_ecr_repo
    
    # -------------------------------------------------------------------------
    # Step 1: Terraform Infrastructure
    # -------------------------------------------------------------------------
    log_step "STEP 1/6: Provisioning Infrastructure with Terraform"
    
    cd terraform
    
    log_info "Initializing Terraform..."
    terraform init -upgrade
    
    log_info "Planning infrastructure changes (this may take a few minutes)..."
    terraform plan \
        -var="github_org=${GITHUB_ORG}" \
        -var="environment=${ENVIRONMENT}" \
        -var="aws_region=${AWS_REGION}" \
        -out=tfplan
    
    log_info "Applying infrastructure (this will take 15-20 minutes)..."
    echo ""
    log_warning "☕ This is a good time to grab coffee!"
    echo ""
    
    terraform apply -auto-approve tfplan
    
    cd ..
    log_success "Infrastructure provisioned successfully"
    
    # -------------------------------------------------------------------------
    # Step 2: Configure kubectl
    # -------------------------------------------------------------------------
    log_step "STEP 2/6: Configuring kubectl"
    
    CLUSTER_NAME=$(cd terraform && terraform output -raw cluster_name)
    aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
    
    # Test connection
    if kubectl cluster-info >/dev/null 2>&1; then
        log_success "Connected to cluster: ${CLUSTER_NAME}"
    else
        log_error "Failed to connect to cluster"
        exit 1
    fi
    
    # -------------------------------------------------------------------------
    # Step 3: Apply Kubernetes Manifests
    # -------------------------------------------------------------------------
    log_step "STEP 3/6: Applying Kubernetes Manifests"
    
    log_info "Creating namespaces..."
    kubectl apply -f manifests/namespaces.yaml
    
    log_info "Applying RBAC configuration..."
    kubectl apply -f manifests/rbac.yaml
    
    log_info "Applying resource quotas..."
    kubectl apply -f manifests/resource-quotas.yaml 2>/dev/null || true
    
    log_success "Base manifests applied"
    
    # -------------------------------------------------------------------------
    # Step 4: Wait for Core Addons
    # -------------------------------------------------------------------------
    log_step "STEP 4/6: Waiting for Core Addons"
    
    # Wait for nodes to be ready
    log_info "Waiting for nodes to be ready..."
    kubectl wait --for=condition=ready nodes --all --timeout=300s 2>/dev/null || true
    kubectl get nodes
    
    # Wait for critical addons (installed by Terraform)
    wait_for_resource "deployment" "aws-load-balancer-controller" "kube-system" 300
    wait_for_resource "deployment" "cluster-autoscaler-aws-cluster-autoscaler" "kube-system" 300
    wait_for_resource "deployment" "argocd-server" "argocd" 300
    wait_for_resource "deployment" "argocd-repo-server" "argocd" 300
    
    # -------------------------------------------------------------------------
    # Step 5: Apply External Secrets
    # -------------------------------------------------------------------------
    log_step "STEP 5/6: Configuring External Secrets Operator"
    
    kubectl apply -f manifests/external-secrets.yaml
    log_success "External Secrets configuration applied"
    
    # -------------------------------------------------------------------------
    # Step 6: Bootstrap ArgoCD (GitOps takes over from here)
    # -------------------------------------------------------------------------
    log_step "STEP 6/6: Bootstrapping ArgoCD GitOps"
    
    log_info "Creating ArgoCD project..."
    kubectl apply -f argocd/projects/platform.yaml
    
    log_info "Deploying app-of-apps (this triggers all platform applications)..."
    kubectl apply -f argocd/apps/app-of-apps.yaml
    
    log_success "ArgoCD GitOps bootstrapped"
    
    # -------------------------------------------------------------------------
    # Post-Bootstrap Information
    # -------------------------------------------------------------------------
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                         🎉 EKS PLATFORM READY! 🎉                          ║"
    echo "╠════════════════════════════════════════════════════════════════════════════╣"
    echo "║                                                                            ║"
    echo "║  Cluster Name:     ${CLUSTER_NAME}                                          "
    echo "║  AWS Region:       ${AWS_REGION}                                            "
    echo "║  Environment:      ${ENVIRONMENT}                                           "
    echo "║  Account ID:       ${ACCOUNT_ID}                                            "
    echo "║                                                                            ║"
    echo "║  ─────────────────────────────────────────────────────────────────────────  ║"
    echo "║  ACCESS COMMANDS:                                                          ║"
    echo "║                                                                            ║"
    
    # Get ArgoCD password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "NOT_READY")
    
    echo "║  ArgoCD UI:                                                                 ║"
    echo "║    kubectl port-forward svc/argocd-server -n argocd 8080:443               ║"
    echo "║    Username: admin                                                         ║"
    echo "║    Password: ${ARGOCD_PASSWORD}                                            ║"
    echo "║                                                                            ║"
    echo "║  Grafana UI:                                                               ║"
    echo "║    kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80 ║"
    echo "║    Username: admin                                                         ║"
    echo "║    Password: admin (CHANGE IN PRODUCTION!)                                 ║"
    echo "║                                                                            ║"
    echo "║  Task API (local):                                                         ║"
    echo "║    kubectl port-forward svc/task-api -n production 8081:80                 ║"
    echo "║    curl http://localhost:8081/health/live                                  ║"
    echo "║                                                                            ║"
    echo "║  ─────────────────────────────────────────────────────────────────────────  ║"
    echo "║  USEFUL COMMANDS:                                                          ║"
    echo "║                                                                            ║"
    echo "║  Check ArgoCD apps:   kubectl get apps -n argocd                           ║"
    echo "║  Check pods:          kubectl get pods -A                                  ║"
    echo "║  Check nodes:         kubectl get nodes -o wide                            ║"
    echo "║  Check HPA:           kubectl get hpa -n production                        ║"
    echo "║  View logs:           kubectl logs -n production deployment/task-api       ║"
    echo "║                                                                            ║"
    echo "║  ─────────────────────────────────────────────────────────────────────────  ║"
    echo "║  ARGOCD SYNC STATUS:                                                       ║"
    echo "║                                                                            ║"
    echo "║  ArgoCD will now sync all applications from:                               ║"
    echo "║    Repo: https://github.com/${GITHUB_ORG}/${MAIN_REPO}                      "
    echo "║    Path: ${SUB_PATH}/argocd/apps                                            "
    echo "║                                                                            ║"
    echo "║  Monitor sync status:                                                      ║"
    echo "║    kubectl get apps -n argocd -w                                           ║"
    echo "║                                                                            ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Save credentials to a file
    cat > platform-credentials.txt << CREDS
EKS Platform Credentials
========================
Date: $(date)
Cluster: ${CLUSTER_NAME}
Region: ${AWS_REGION}
Account: ${ACCOUNT_ID}

ArgoCD:
  URL: kubectl port-forward svc/argocd-server -n argocd 8080:443
  Username: admin
  Password: ${ARGOCD_PASSWORD}

Grafana:
  URL: kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80
  Username: admin
  Password: admin

Repository:
  URL: https://github.com/${GITHUB_ORG}/${MAIN_REPO}
  Path: ${SUB_PATH}
CREDS
    
    log_success "Credentials saved to: platform-credentials.txt"
    log_warning "IMPORTANT: Keep platform-credentials.txt secure!"
    echo ""
    log_info "Monitor ArgoCD sync: kubectl get apps -n argocd -w"
}

# Run main function
main "$@"
