#!/usr/bin/env bash
# ABOUTME: Integration tests for Tier 2 tools (Prometheus Stack, ArgoCD, External Secrets).
# ABOUTME: Requires a running AKS cluster with Tier 2 installed.
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0
skipped=0

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

skip() {
    echo -e "  ${YELLOW}⊘${NC} $1"
    skipped=$((skipped + 1))
}

echo -e "${BOLD}── Tier 2 Integration Tests ──${NC}"
echo ""

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to cluster.${NC}"
    exit 1
fi

# --- PROMETHEUS STACK ---
echo -e "${BOLD}Prometheus Stack:${NC}"
prom_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Prometheus pod running" "$([ "$prom_pods" -gt 0 ] && echo true || echo false)"

grafana_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Grafana pod running" "$([ "$grafana_pods" -gt 0 ] && echo true || echo false)"

alertmanager_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Alertmanager pod running" "$([ "$alertmanager_pods" -gt 0 ] && echo true || echo false)"

# Check ServiceMonitors exist
svc_monitors=$(kubectl get servicemonitors -n monitoring --no-headers 2>/dev/null | wc -l || echo "0")
check "ServiceMonitors deployed (>= 1)" "$([ "$svc_monitors" -ge 1 ] && echo true || echo false)"
echo ""

# --- ARGOCD ---
echo -e "${BOLD}ArgoCD:${NC}"
argocd_server=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "ArgoCD server running" "$([ "$argocd_server" -gt 0 ] && echo true || echo false)"

argocd_repo=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "ArgoCD repo-server running" "$([ "$argocd_repo" -gt 0 ] && echo true || echo false)"

argocd_controller=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "ArgoCD application-controller running" "$([ "$argocd_controller" -gt 0 ] && echo true || echo false)"
echo ""

# --- EXTERNAL SECRETS ---
echo -e "${BOLD}External Secrets Operator:${NC}"
eso_pods=$(kubectl get pods -n external-secrets -l app.kubernetes.io/name=external-secrets --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "ESO controller running" "$([ "$eso_pods" -gt 0 ] && echo true || echo false)"

eso_crd=$(kubectl get crd externalsecrets.external-secrets.io 2>/dev/null && echo "true" || echo "false")
check "ExternalSecret CRD registered" "$eso_crd"
echo ""

# Results
echo -e "${BOLD}── Results ──${NC}"
echo -e "  ${GREEN}Passed:  ${passed}${NC}"
echo -e "  ${RED}Failed:  ${failed}${NC}"
echo -e "  ${YELLOW}Skipped: ${skipped}${NC}"

[[ $failed -eq 0 ]] && exit 0 || exit 1
