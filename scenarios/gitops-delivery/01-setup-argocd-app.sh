#!/usr/bin/env bash
# ABOUTME: Sets up ArgoCD project, application, and kustomize overlay for GitOps demo.
# ABOUTME: Step 1 of the GitOps delivery scenario — creates the ArgoCD application CR.
# ============================================================================
#
# STEP 1: SETUP ARGOCD APPLICATION
#
# This script:
#   1. Applies the ArgoCD AppProject (regulated-apps) with RBAC controls
#   2. Creates an ArgoCD Application pointing to the kustomize production overlay
#   3. Verifies the application syncs successfully
#
# PREREQUISITES:
#   - AKS cluster with tools installed (install-tools.sh --tier=1,2)
#   - ArgoCD running in the argocd namespace
#   - kubectl context set to the target cluster
#
# REGULATORY ALIGNMENT:
#   - NCUA/FFIEC: Change management via Git-based deployments
#   - DORA Article 9: ICT change management with audit trail
#   - SOC 2 CC8.1: Controlled changes with approval workflows
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
NC='\033[0m'

# ----------------------------------------------------------------------------
# HELPER FUNCTIONS
# ----------------------------------------------------------------------------
info()    { echo -e "${CYAN}  ℹ ${NC} $*"; }
success() { echo -e "${GREEN}  ✓ ${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠ ${NC} $*"; }
error()   { echo -e "${RED}  ✗ ${NC} $*"; }

# ----------------------------------------------------------------------------
# PREFLIGHT CHECKS
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Step 1: Setup ArgoCD Application ──${NC}"
echo ""

# Verify ArgoCD is running
info "Checking ArgoCD availability..."
if ! kubectl get deploy -n argocd argocd-server >/dev/null 2>&1; then
    error "ArgoCD not found. Run: ./scripts/install-tools.sh --tier=2"
    exit 1
fi
success "ArgoCD server found in argocd namespace"

# Verify ArgoCD pods are ready
argocd_ready=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [[ "$argocd_ready" -eq 0 ]]; then
    warn "ArgoCD server pod not yet Running. Waiting..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server \
        -n argocd --timeout=120s 2>/dev/null || {
        error "ArgoCD server did not become ready. Check: kubectl get pods -n argocd"
        exit 1
    }
fi
success "ArgoCD server pod is Running"
echo ""

# ----------------------------------------------------------------------------
# STEP 1a: APPLY ARGOCD PROJECT
# ----------------------------------------------------------------------------
info "Applying ArgoCD AppProject (regulated-apps)..."
echo ""

if [[ -f "${ROOT_DIR}/tools/argocd/manifests/project.yaml" ]]; then
    kubectl apply -f "${ROOT_DIR}/tools/argocd/manifests/project.yaml"
    success "AppProject 'regulated-apps' created"
else
    warn "Project manifest not found, creating inline..."
    kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: regulated-apps
  namespace: argocd
spec:
  description: Regulated workloads with source and destination restrictions
  sourceRepos:
    - '*'
  destinations:
    - server: https://kubernetes.default.svc
      namespace: '*'
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
EOF
    success "AppProject 'regulated-apps' created (inline)"
fi
echo ""

# ----------------------------------------------------------------------------
# STEP 1b: CREATE ARGOCD APPLICATION FOR KUSTOMIZE OVERLAY
# ----------------------------------------------------------------------------
info "Creating ArgoCD Application for production kustomize overlay..."
echo ""

# Detect the repo URL from git remote
REPO_URL=$(git -C "${ROOT_DIR}" remote get-url origin 2>/dev/null || echo "")
if [[ -z "$REPO_URL" ]]; then
    REPO_URL="https://github.com/peopleforrester/webinar_k8s_in_regulated_enterprises.git"
    warn "Could not detect git remote; using default: ${REPO_URL}"
fi

# Convert SSH URL to HTTPS if needed (ArgoCD prefers HTTPS for public repos)
if [[ "$REPO_URL" == git@* ]]; then
    REPO_URL=$(echo "$REPO_URL" | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||').git
fi

# Get current branch for targetRevision
TARGET_REVISION=$(git -C "${ROOT_DIR}" branch --show-current 2>/dev/null || echo "HEAD")

info "Repo URL: ${REPO_URL}"
info "Target revision: ${TARGET_REVISION}"
echo ""

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-app-production
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: regulated-demo
    scenario: gitops-delivery
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: regulated-apps
  source:
    repoURL: ${REPO_URL}
    targetRevision: ${TARGET_REVISION}
    path: tools/kustomize/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: demo-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 1m
EOF

success "ArgoCD Application 'demo-app-production' created"
echo ""

# ----------------------------------------------------------------------------
# STEP 1c: WAIT FOR INITIAL SYNC
# ----------------------------------------------------------------------------
info "Waiting for ArgoCD to sync the application..."
echo ""

# Poll for sync status (ArgoCD takes a moment to detect the new app)
retries=0
max_retries=30
while [[ $retries -lt $max_retries ]]; do
    sync_status=$(kubectl get application demo-app-production -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    health_status=$(kubectl get application demo-app-production -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
        success "Application synced and healthy!"
        break
    fi

    echo -e "  Sync: ${sync_status}, Health: ${health_status} (attempt $((retries+1))/${max_retries})"
    retries=$((retries + 1))
    sleep 10
done

if [[ $retries -eq $max_retries ]]; then
    warn "Application may still be syncing. Check: kubectl get application -n argocd"
fi
echo ""

# ----------------------------------------------------------------------------
# STEP 1d: DISPLAY RESULTS
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Application Status ──${NC}"
echo ""
kubectl get application demo-app-production -n argocd 2>/dev/null || true
echo ""

# Show deployed resources
info "Resources deployed by ArgoCD:"
kubectl get all -n demo-app 2>/dev/null || info "Namespace 'demo-app' not yet created (sync may be in progress)"
echo ""

# Show ArgoCD admin password for UI access
info "ArgoCD UI access:"
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "N/A")
echo "  URL:      kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""

success "Step 1 complete. ArgoCD is managing the kustomize production overlay."
echo "  Next: Run 02-trigger-sync.sh to demonstrate Git-driven deployment."
