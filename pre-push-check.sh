#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error counter
ERRORS=0

print_section() {
    echo ""
    echo "=========================================="
    echo "=== $1"
    echo "=========================================="
}

check_result() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $1 passed${NC}"
        return 0
    else
        echo -e "${RED}❌ $1 failed${NC}"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

cd ~/aws-cloud-engineer-projects

print_section "1. Code Quality (Flake8)"
cd aws-ci_cd-pipeline-terraform
flake8 app/ --max-line-length=120 --exclude=app/tests/,app/venv,app/__pycache__ --count
check_result "Flake8"

print_section "2. Unit Tests (Pytest)"
cd ~/aws-cloud-engineer-projects/aws-ci_cd-pipeline-terraform
if [ -d "venv" ]; then
    source venv/bin/activate
    PYTHONPATH=./app pytest app/tests/ -v -q
    check_result "Pytest"
    deactivate
else
    echo -e "${YELLOW}⚠️ Virtual environment not found, creating one...${NC}"
    python3 -m venv venv
    source venv/bin/activate
    pip install -q -r app/requirements.txt
    pip install -q -r app/requirements-dev.txt
    PYTHONPATH=./app pytest app/tests/ -v -q
    check_result "Pytest"
    deactivate
fi

print_section "3. Docker Build"
cd ~/aws-cloud-engineer-projects/aws-ci_cd-pipeline-terraform
docker build -f app/Dockerfile -t test-api ./app > /dev/null 2>&1
check_result "Docker build"

print_section "4. Docker Run & Health Check"
# Use port 8081 to avoid conflicts with Airflow
PORT=8081
echo "Using port $PORT for testing"

docker run -d --name test-api-container -p $PORT:8080 test-api > /dev/null 2>&1
sleep 5

curl -s http://localhost:$PORT/health/live | grep -q "alive"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Health check passed${NC}"
else
    echo -e "${RED}❌ Health check failed${NC}"
    docker logs test-api-container
    ERRORS=$((ERRORS + 1))
fi

docker stop test-api-container > /dev/null 2>&1
docker rm test-api-container > /dev/null 2>&1
docker rmi test-api > /dev/null 2>&1

print_section "5. Terraform Validation"
cd ~/aws-cloud-engineer-projects/aws-ci_cd-pipeline-terraform/terraform
terraform fmt > /dev/null 2>&1
check_result "Terraform fmt"

terraform validate > /dev/null 2>&1
check_result "Terraform validate"

cd ~/aws-cloud-engineer-projects

echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL CHECKS PASSED - Ready to push to GitHub!${NC}"
else
    echo -e "${RED}❌ $ERRORS check(s) failed. Please fix before pushing.${NC}"
fi
echo "=========================================="

exit $ERRORS
