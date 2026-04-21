#!/bin/bash
set -euo pipefail

APP_NAME="${1:-task-api}"
REVISION="${2:-1}"
NAMESPACE="${3:-production}"

echo "🔄 Rolling back ${APP_NAME} to revision ${REVISION} in ${NAMESPACE}..."

# Option 1: Helm rollback (if using Helm directly)
# helm rollback ${APP_NAME} ${REVISION} -n ${NAMESPACE}

# Option 2: ArgoCD rollback (sync to previous commit)
kubectl -n argocd patch application ${APP_NAME} \
    --type='json' \
    -p='[{"op": "replace", "path": "/spec/source/targetRevision", "value": "HEAD~1"}]'

# Force sync
kubectl -n argocd patch application ${APP_NAME} \
    --type merge \
    -p '{"operation": {"sync": {"revision": "HEAD~1"}}}'

echo "✅ Rollback initiated. Check status with: kubectl get apps -n argocd ${APP_NAME}"
