#!/usr/bin/env bash
# ABOUTME: Integration tests for Tier 3 platform tools (Istio, Crossplane, Harbor).
# ABOUTME: Requires a running AKS cluster with Tier 3 installed.
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

echo -e "${BOLD}── Tier 3 Integration Tests ──${NC}"
echo ""

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to cluster.${NC}"
    exit 1
fi

# --- ISTIO ---
echo -e "${BOLD}Istio:${NC}"
istiod_pods=$(kubectl get pods -n istio-system -l app=istiod --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "istiod pod running" "$([ "$istiod_pods" -gt 0 ] && echo true || echo false)"

istio_crd=$(kubectl get crd virtualservices.networking.istio.io 2>/dev/null && echo "true" || echo "false")
check "Istio CRDs registered" "$istio_crd"

peer_auth=$(kubectl get peerauthentication -n istio-system --no-headers 2>/dev/null | wc -l || echo "0")
check "PeerAuthentication policy applied" "$([ "$peer_auth" -gt 0 ] && echo true || echo false)"
echo ""

# --- CROSSPLANE ---
echo -e "${BOLD}Crossplane:${NC}"
crossplane_pods=$(kubectl get pods -n crossplane-system -l app=crossplane --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Crossplane pod running" "$([ "$crossplane_pods" -gt 0 ] && echo true || echo false)"

providers=$(kubectl get providers --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$providers" -gt 0 ]]; then
    check "Crossplane providers installed" "true"
    # Check provider health
    healthy=$(kubectl get providers --no-headers 2>/dev/null | grep -c "True" || echo "0")
    check "Crossplane providers healthy" "$([ "$healthy" -gt 0 ] && echo true || echo false)"
else
    skip "No Crossplane providers installed"
fi
echo ""

# --- HARBOR ---
echo -e "${BOLD}Harbor:${NC}"
harbor_core=$(kubectl get pods -n harbor -l app=harbor -l component=core --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Harbor core pod running" "$([ "$harbor_core" -gt 0 ] && echo true || echo false)"

harbor_portal=$(kubectl get pods -n harbor -l app=harbor -l component=portal --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Harbor portal pod running" "$([ "$harbor_portal" -gt 0 ] && echo true || echo false)"

harbor_registry=$(kubectl get pods -n harbor -l app=harbor -l component=registry --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Harbor registry pod running" "$([ "$harbor_registry" -gt 0 ] && echo true || echo false)"
echo ""

# Results
echo -e "${BOLD}── Results ──${NC}"
echo -e "  ${GREEN}Passed:  ${passed}${NC}"
echo -e "  ${RED}Failed:  ${failed}${NC}"
echo -e "  ${YELLOW}Skipped: ${skipped}${NC}"

[[ $failed -eq 0 ]] && exit 0 || exit 1
