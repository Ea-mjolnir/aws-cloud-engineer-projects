#!/bin/bash
set -euo pipefail

# ─── Blue-Green Deployment Orchestrator ───────────────────────────────────────
# Usage: ./scripts/blue_green_deploy.sh <image_tag>

IMAGE_TAG=${1:?"Image tag required. Usage: $0 <tag>"}
CLUSTER="${PROJECT_NAME:-cicd-pipeline}-cluster"
SERVICE="${PROJECT_NAME:-cicd-pipeline}-api"
REGION="${AWS_REGION:-us-east-1}"

echo "🚀 Starting blue-green deployment"
echo "   Image tag:  $IMAGE_TAG"
echo "   Cluster:    $CLUSTER"
echo "   Service:    $SERVICE"

# Get current task definition
CURRENT_TASK_DEF=$(aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region "$REGION" \
  --query 'services[0].taskDefinition' \
  --output text)

echo "📋 Current task definition: $CURRENT_TASK_DEF"

# Get ECR repository URL
ECR_REPO=$(aws ecs describe-task-definition \
  --task-definition "$CURRENT_TASK_DEF" \
  --region "$REGION" \
  --query 'taskDefinition.containerDefinitions[0].image' \
  --output text | cut -d: -f1)

NEW_IMAGE="${ECR_REPO}:${IMAGE_TAG}"
echo "🐳 New image: $NEW_IMAGE"

# Register new task definition with updated image
NEW_TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition "$CURRENT_TASK_DEF" \
  --region "$REGION" \
  --query 'taskDefinition' \
  --output json | \
  jq --arg IMAGE "$NEW_IMAGE" \
     '.containerDefinitions[0].image = $IMAGE |
      del(.taskDefinitionArn, .revision, .status,
          .requiresAttributes, .placementConstraints,
          .compatibilities, .registeredAt, .registeredBy)' | \
  aws ecs register-task-definition \
    --region "$REGION" \
    --cli-input-json /dev/stdin \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "📝 Registered new task definition: $NEW_TASK_DEF"

# Update service with new task definition
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$NEW_TASK_DEF" \
  --region "$REGION" \
  --output text > /dev/null

echo "⏳ Waiting for service to stabilize..."

# Wait for deployment to complete (max 10 minutes)
timeout 600 aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region "$REGION"

echo "✅ Deployment complete — $SERVICE is running $IMAGE_TAG"
