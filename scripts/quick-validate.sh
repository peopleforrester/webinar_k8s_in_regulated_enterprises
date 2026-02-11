#!/bin/bash
# ABOUTME: Quick validation script for AKS cluster with all tool tiers.
# ABOUTME: Checks connectivity, tool health, and policy enforcement across tiers.

set -euo pipefail

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tier1-security.sh"
source "${SCRIPT_DIR}/lib/tier2-observability.sh"
source "${SCRIPT_DIR}/lib/tier3-platform.sh"
source "${SCRIPT_DIR}/lib/tier4-aks-managed.sh"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         QUICK VALIDATION — AKS Regulated Demo               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

#######################################
# 1. Cluster Connection
#######################################
echo "1. Checking cluster connection..."
if kubectl cluster-info &>/dev/null; then
    CLUSTER=$(kubectl config current-context)
    echo -e "  ${GREEN}✓${NC} Connected to: $CLUSTER"
else
    echo -e "  ${RED}✗${NC} Not connected to a cluster. Run: az aks get-credentials ..."
    exit 1
fi

#######################################
# 2. Tier-by-Tier Validation
#######################################
TOTAL_ISSUES=0

echo ""
echo "───────────────────────────────────────"
validate_tier1 || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))

echo ""
echo "───────────────────────────────────────"
validate_tier2 || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))

echo ""
echo "───────────────────────────────────────"
validate_tier3 || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))

echo ""
echo "───────────────────────────────────────"
validate_tier4 || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))

#######################################
# 3. Demo Workloads
#######################################
echo ""
echo "───────────────────────────────────────"
echo "Checking demo workloads..."

for ns in vulnerable-app compliant-app; do
    if kubectl get namespace "${ns}" &>/dev/null; then
        local_pods=$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null | wc -l || echo "0")
        echo -e "  ${GREEN}✓${NC} ${ns}: ${local_pods} pod(s)"
    else
        echo -e "  ${YELLOW}⚠${NC} ${ns}: namespace not found"
    fi
done

#######################################
# 4. Quick Policy Test
#######################################
echo ""
echo "───────────────────────────────────────"
echo "Quick policy test (attempting privileged pod dry-run)..."

KYVERNO_RUNNING=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [[ "$KYVERNO_RUNNING" -gt 0 ]]; then
    TEST_RESULT=$(kubectl run test-privileged --image=nginx --restart=Never \
        --overrides='{"spec":{"containers":[{"name":"nginx","image":"nginx","securityContext":{"privileged":true}}]}}' \
        --dry-run=server -o yaml 2>&1 || true)

    if echo "$TEST_RESULT" | grep -qi "blocked\|denied\|disallow"; then
        echo -e "  ${GREEN}✓${NC} Kyverno correctly blocked privileged pod"
    else
        echo -e "  ${YELLOW}⚠${NC} Privileged pod was not blocked (policies may not be applied yet)"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} Kyverno not running — skipping policy test"
fi

#######################################
# Summary
#######################################
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "VALIDATION SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [[ $TOTAL_ISSUES -eq 0 ]]; then
    echo -e "${GREEN}All checked tools are operational.${NC}"
    echo ""
    echo "Suggested next steps:"
    echo "  1. Run attack simulation:  ./scenarios/attack-detect-prevent/01-reconnaissance.sh"
    echo "  2. Watch Falco logs:       kubectl logs -n falco -l app.kubernetes.io/name=falco -f"
    echo "  3. Run compliance scan:    kubescape scan framework cis-v1.12.0"
else
    echo -e "${YELLOW}${TOTAL_ISSUES} issue(s) found. Address before running demos.${NC}"
fi
echo ""
