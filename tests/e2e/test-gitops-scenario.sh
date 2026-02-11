#!/usr/bin/env bash
# ABOUTME: End-to-end test for the GitOps delivery scenario.
# ABOUTME: Creates ArgoCD application, verifies sync, checks Trivy scanning.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0

check() {
    local name="$1"
    local result="$2"
    if [[ "$result" == "true" ]]; then
        echo -e "  ${GREEN}✓${NC} ${name}"
        passed=$((passed + 1))
    else
        echo -e "  ${RED}✗${NC} ${name}"
        failed=$((failed + 1))
    fi
}

echo -e "${BOLD}── E2E: GitOps Delivery Scenario ──${NC}"
echo ""

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to cluster.${NC}"
    exit 1
fi

# Pre-check: ArgoCD and Trivy must be running
argocd_ok=$(kubectl get deploy -n argocd argocd-server 2>/dev/null && echo "true" || echo "false")
check "ArgoCD server available" "$argocd_ok"

trivy_ok=$(kubectl get deploy -n trivy-system trivy-operator 2>/dev/null && echo "true" || echo "false")
check "Trivy Operator available" "$trivy_ok"
echo ""

if [[ "$argocd_ok" != "true" ]]; then
    echo -e "${YELLOW}ArgoCD not available — skipping GitOps e2e test${NC}"
    exit 0
fi

# Step 1: Create ArgoCD Application
echo -e "${BOLD}Step 1: Create ArgoCD Application${NC}"
kubectl apply -f "${ROOT_DIR}/tools/argocd/manifests/project.yaml" 2>/dev/null || true

REPO_URL=$(git -C "${ROOT_DIR}" remote get-url origin 2>/dev/null | sed 's|git@github.com:|https://github.com/|' || echo "https://github.com/peopleforrester/webinar_k8s_in_regulated_enterprises.git")

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: e2e-gitops-test
  namespace: argocd
spec:
  project: regulated-apps
  source:
    repoURL: ${REPO_URL}
    targetRevision: HEAD
    path: tools/kustomize/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: e2e-gitops-test
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
check "ArgoCD Application created" "true"
echo ""

# Step 2: Wait for sync
echo -e "${BOLD}Step 2: Wait for ArgoCD sync${NC}"
retries=0
synced=false
while [[ $retries -lt 20 ]]; do
    status=$(kubectl get application e2e-gitops-test -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
    health=$(kubectl get application e2e-gitops-test -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
    if [[ "$status" == "Synced" && "$health" == "Healthy" ]]; then
        synced=true
        break
    fi
    retries=$((retries + 1))
    sleep 10
done
check "Application synced and healthy" "$synced"
echo ""

# Step 3: Verify deployed resources
echo -e "${BOLD}Step 3: Verify deployed resources${NC}"
pods=$(kubectl get pods -n e2e-gitops-test --no-headers 2>/dev/null | wc -l || echo "0")
check "Pods deployed in e2e-gitops-test (>= 1)" "$([ "$pods" -ge 1 ] && echo true || echo false)"
echo ""

# Step 4: Check Trivy scanning
echo -e "${BOLD}Step 4: Check Trivy scanning${NC}"
if [[ "$trivy_ok" == "true" ]]; then
    # Wait for Trivy to scan
    sleep 15
    reports=$(kubectl get vulnerabilityreports -n e2e-gitops-test --no-headers 2>/dev/null | wc -l || echo "0")
    check "VulnerabilityReports generated" "$([ "$reports" -gt 0 ] && echo true || echo false)"
else
    echo -e "  ${YELLOW}⊘${NC} Trivy not available (skipping scan check)"
fi
echo ""

# Cleanup
echo -e "${BOLD}Cleanup:${NC}"
kubectl delete application e2e-gitops-test -n argocd 2>/dev/null || true
kubectl delete namespace e2e-gitops-test --wait=false 2>/dev/null || true
echo "  Cleaned up e2e-gitops-test resources"
echo ""

# Results
echo -e "${BOLD}── Results ──${NC}"
echo -e "  ${GREEN}Passed: ${passed}${NC}"
echo -e "  ${RED}Failed: ${failed}${NC}"

[[ $failed -eq 0 ]] && exit 0 || exit 1
