#!/bin/bash
set -euo pipefail

# ─── Post-deployment health validation ────────────────────────────────────────
ENDPOINT=${1:?"ALB endpoint required. Usage: $0 <endpoint>"}
MAX_RETRIES=20
RETRY_INTERVAL=15

echo "🔍 Running post-deployment health checks against $ENDPOINT"

# 1. Liveness check
echo "  Checking /health/live..."
for i in $(seq 1 $MAX_RETRIES); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT/health/live")
  if [ "$STATUS" = "200" ]; then
    echo "  ✅ Liveness check passed"
    break
  fi
  if [ "$i" = "$MAX_RETRIES" ]; then
    echo "  ❌ Liveness check failed after $MAX_RETRIES attempts"
    exit 1
  fi
  echo "  Attempt $i/$MAX_RETRIES — status $STATUS, retrying in ${RETRY_INTERVAL}s..."
  sleep $RETRY_INTERVAL
done

# 2. Readiness check
echo "  Checking /health/ready..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT/health/ready")
[ "$STATUS" = "200" ] && echo "  ✅ Readiness check passed" || { echo "  ❌ Readiness failed — status $STATUS"; exit 1; }

# 3. Deep health check
echo "  Checking /health..."
HEALTH=$(curl -s "$ENDPOINT/health")
HEALTH_STATUS=$(echo "$HEALTH" | jq -r '.status')
[ "$HEALTH_STATUS" = "healthy" ] && echo "  ✅ Deep health check passed" || {
  echo "  ⚠️  Health status: $HEALTH_STATUS"
  echo "  Details: $HEALTH"
}

# 4. Version verification
VERSION=$(echo "$HEALTH" | jq -r '.version')
echo "  ✅ Running version: $VERSION"

echo "🎉 All health checks passed!"
