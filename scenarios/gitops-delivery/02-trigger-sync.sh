#!/usr/bin/env bash
# ABOUTME: Demonstrates Git-driven deployments by modifying kustomize overlay and watching ArgoCD sync.
# ABOUTME: Step 2 of the GitOps delivery scenario — shows change management via Git.
# ============================================================================
#
# STEP 2: TRIGGER A GITOPS SYNC
#
# This script demonstrates the GitOps workflow:
#   1. Show current state of the deployed application
#   2. Make a change to the kustomize overlay (scale replicas)
#   3. Commit and push the change
#   4. Watch ArgoCD detect and sync the change
#   5. Verify the updated deployment
#
# THE GITOPS PROMISE:
#   Every change is traceable to a Git commit. No kubectl apply in production.
#   ArgoCD watches the repo and reconciles drift automatically.
#
# PREREQUISITES:
#   - Step 01 completed (ArgoCD Application created)
#   - Git push access to the repository
#
# REGULATORY ALIGNMENT:
#   - NCUA Part 748: Every deployment traceable to an approved change
#   - DORA Article 9: Automated change management with audit trail
#   - PCI-DSS 6.4: Separation of environments via kustomize overlays
#   - SOC 2 CC8.1: Changes tracked in version control
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."

# Terminal colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${CYAN}  ℹ ${NC} $*"; }
success() { echo -e "${GREEN}  ✓ ${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠ ${NC} $*"; }
error()   { echo -e "${RED}  ✗ ${NC} $*"; }

pause() {
    echo ""
    echo -e "${BLUE}  Press Enter to continue...${NC}"
    read -r
}

# ----------------------------------------------------------------------------
# PREFLIGHT
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Step 2: Trigger GitOps Sync ──${NC}"
echo ""

# Verify the application exists
if ! kubectl get application demo-app-production -n argocd >/dev/null 2>&1; then
    error "ArgoCD Application 'demo-app-production' not found."
    error "Run 01-setup-argocd-app.sh first."
    exit 1
fi

# ----------------------------------------------------------------------------
# STEP 2a: SHOW CURRENT STATE
# ----------------------------------------------------------------------------
info "Current application state:"
echo ""
kubectl get application demo-app-production -n argocd -o wide 2>/dev/null || true
echo ""

info "Current deployment replicas:"
current_replicas=$(kubectl get deploy -n demo-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "unknown")
echo "  Replicas: ${current_replicas}"
echo ""

# Determine target replicas (toggle between 2 and 3)
if [[ "$current_replicas" == "3" ]]; then
    new_replicas=2
else
    new_replicas=3
fi

info "Will scale from ${current_replicas} to ${new_replicas} replicas via Git."
pause

# ----------------------------------------------------------------------------
# STEP 2b: MODIFY KUSTOMIZE OVERLAY
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Modifying kustomize overlay via Git ──${NC}"
echo ""

OVERLAY_FILE="${ROOT_DIR}/tools/kustomize/overlays/production/kustomization.yaml"

info "Updating replica count in production overlay..."
# Use sed to update the replicas value in the kustomization patch
if grep -q "replicas:" "${OVERLAY_FILE}" 2>/dev/null; then
    sed -i "s/replicas: [0-9]*/replicas: ${new_replicas}/" "${OVERLAY_FILE}"
    success "Updated replicas to ${new_replicas} in production overlay"
else
    warn "Could not find replicas field in overlay. The sync will proceed with existing config."
fi
echo ""

# Show the diff
info "Git diff:"
git -C "${ROOT_DIR}" diff -- tools/kustomize/overlays/production/ 2>/dev/null || true
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 2c: COMMIT AND PUSH
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Committing change to Git ──${NC}"
echo ""

info "Committing the replica change..."

cd "${ROOT_DIR}"
git add tools/kustomize/overlays/production/kustomization.yaml
git commit -m "Scale production overlay to ${new_replicas} replicas

GitOps demo: Automated deployment via ArgoCD sync.
Change tracked in Git for audit compliance." 2>&1 || {
    warn "Nothing to commit (overlay may already be at target state)"
}

info "Pushing to remote..."
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "staging")
if git push origin "${CURRENT_BRANCH}" 2>&1; then
    success "Changes pushed to ${CURRENT_BRANCH}"
else
    warn "Push failed. ArgoCD will sync on next manual refresh."
    warn "You can trigger manually: kubectl patch application demo-app-production -n argocd --type merge -p '{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"normal\"}}}'"
fi
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 2d: WATCH ARGOCD SYNC
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Watching ArgoCD sync ──${NC}"
echo ""

info "Triggering ArgoCD refresh..."
kubectl patch application demo-app-production -n argocd \
    --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}' 2>/dev/null || true
echo ""

info "Waiting for ArgoCD to detect and apply the change..."
retries=0
max_retries=30
while [[ $retries -lt $max_retries ]]; do
    sync_status=$(kubectl get application demo-app-production -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    health_status=$(kubectl get application demo-app-production -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    actual_replicas=$(kubectl get deploy -n demo-app -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")

    echo -e "  Sync: ${sync_status} | Health: ${health_status} | Ready: ${actual_replicas}/${new_replicas}"

    if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" && "$actual_replicas" == "$new_replicas" ]]; then
        echo ""
        success "ArgoCD synced successfully!"
        break
    fi

    retries=$((retries + 1))
    sleep 10
done

if [[ $retries -eq $max_retries ]]; then
    warn "Sync may still be in progress. Check ArgoCD UI for details."
fi
echo ""

# ----------------------------------------------------------------------------
# STEP 2e: VERIFY
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Verification ──${NC}"
echo ""

info "Deployed resources:"
kubectl get all -n demo-app 2>/dev/null || true
echo ""

info "ArgoCD application status:"
kubectl get application demo-app-production -n argocd 2>/dev/null || true
echo ""

# Show the Git history for audit trail
info "Git audit trail (recent commits):"
git -C "${ROOT_DIR}" log --oneline -5
echo ""

success "Step 2 complete. Deployment updated via Git — no kubectl apply needed."
echo ""
echo -e "${YELLOW}Key regulatory takeaways:${NC}"
echo "  - Every deployment change traces to a Git commit (audit trail)"
echo "  - No manual kubectl access required for production changes"
echo "  - ArgoCD auto-heals drift (selfHeal: true)"
echo "  - Kustomize overlays separate dev/staging/prod configs"
echo ""
echo "  Next: Run 03-vulnerable-image-gate.sh to see Trivy block a bad image."
