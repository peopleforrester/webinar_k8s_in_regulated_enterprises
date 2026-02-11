#!/usr/bin/env bash
# ABOUTME: Integration tests for Tier 1 security tools (Falco, Kyverno, Trivy, Kubescape).
# ABOUTME: Requires a running AKS cluster with Tier 1 installed.
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

echo -e "${BOLD}── Tier 1 Integration Tests ──${NC}"
echo ""

# Verify cluster connectivity
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to cluster. Set kubeconfig and retry.${NC}"
    exit 1
fi

# --- FALCO ---
echo -e "${BOLD}Falco:${NC}"
falco_pods=$(kubectl get pods -n falco -l app.kubernetes.io/name=falco --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Falco DaemonSet pods running" "$([ "$falco_pods" -gt 0 ] && echo true || echo false)"

falco_crd=$(kubectl get crd falcorules.falcosecurity.org 2>/dev/null && echo "true" || echo "false")
check "Falco CRD registered" "$falco_crd"
echo ""

# --- FALCOSIDEKICK ---
echo -e "${BOLD}Falcosidekick:${NC}"
sidekick_pods=$(kubectl get pods -n falco -l app.kubernetes.io/name=falcosidekick --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Falcosidekick pod running" "$([ "$sidekick_pods" -gt 0 ] && echo true || echo false)"
echo ""

# --- FALCO TALON ---
echo -e "${BOLD}Falco Talon:${NC}"
talon_pods=$(kubectl get pods -n falco -l app.kubernetes.io/name=falco-talon --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [[ "$talon_pods" -gt 0 ]]; then
    check "Falco Talon pod running" "true"
else
    skip "Falco Talon not installed (optional)"
fi
echo ""

# --- KYVERNO ---
echo -e "${BOLD}Kyverno:${NC}"
kyverno_pods=$(kubectl get pods -n kyverno -l app.kubernetes.io/component=admission-controller --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Kyverno admission controller running" "$([ "$kyverno_pods" -gt 0 ] && echo true || echo false)"

policies=$(kubectl get clusterpolicies --no-headers 2>/dev/null | wc -l || echo "0")
check "ClusterPolicies deployed (>= 1)" "$([ "$policies" -ge 1 ] && echo true || echo false)"
echo ""

# --- TRIVY ---
echo -e "${BOLD}Trivy Operator:${NC}"
trivy_pods=$(kubectl get pods -n trivy-system -l app.kubernetes.io/name=trivy-operator --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Trivy Operator pod running" "$([ "$trivy_pods" -gt 0 ] && echo true || echo false)"

trivy_crd=$(kubectl get crd vulnerabilityreports.aquasecurity.github.io 2>/dev/null && echo "true" || echo "false")
check "VulnerabilityReport CRD registered" "$trivy_crd"
echo ""

# --- KUBESCAPE ---
echo -e "${BOLD}Kubescape:${NC}"
ks_pods=$(kubectl get pods -n kubescape --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Kubescape pods running (>= 1)" "$([ "$ks_pods" -ge 1 ] && echo true || echo false)"
echo ""

# Results
echo -e "${BOLD}── Results ──${NC}"
echo -e "  ${GREEN}Passed:  ${passed}${NC}"
echo -e "  ${RED}Failed:  ${failed}${NC}"
echo -e "  ${YELLOW}Skipped: ${skipped}${NC}"

[[ $failed -eq 0 ]] && exit 0 || exit 1
