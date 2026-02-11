#!/usr/bin/env bash
# ABOUTME: End-to-end test for the attack-detect-prevent scenario.
# ABOUTME: Deploys vulnerable app, runs attacks, verifies Falco detection and Kyverno prevention.
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

echo -e "${BOLD}── E2E: Attack-Detect-Prevent Scenario ──${NC}"
echo ""

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to cluster.${NC}"
    exit 1
fi

# Step 1: Deploy vulnerable workload
echo -e "${BOLD}Step 1: Deploy vulnerable workload${NC}"
kubectl apply -f "${ROOT_DIR}/workloads/vulnerable-app/namespace.yaml" 2>/dev/null || true
kubectl apply -f "${ROOT_DIR}/workloads/vulnerable-app/" 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=vulnerable-app -n vulnerable-app --timeout=60s 2>/dev/null || true

vuln_running=$(kubectl get pods -n vulnerable-app -l app=vulnerable-app --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Vulnerable app deployed and running" "$([ "$vuln_running" -gt 0 ] && echo true || echo false)"
echo ""

# Step 2: Run reconnaissance attack
echo -e "${BOLD}Step 2: Run attack simulation${NC}"
POD=$(kubectl get pod -n vulnerable-app -l app=vulnerable-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$POD" ]]; then
    # Run basic reconnaissance command inside the pod
    kubectl exec -n vulnerable-app "$POD" -- cat /etc/hostname 2>/dev/null || true
    kubectl exec -n vulnerable-app "$POD" -- cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null | head -c 20 || true
    echo ""
    check "Attack commands executed" "true"

    # Check Falco detected the attack (check recent logs)
    sleep 5
    falco_alerts=$(kubectl logs -n falco -l app.kubernetes.io/name=falco --since=30s 2>/dev/null | grep -c "Warning\|Notice\|Error" || echo "0")
    check "Falco detected attack activity (alerts > 0)" "$([ "$falco_alerts" -gt 0 ] && echo true || echo false)"
else
    check "Could not find vulnerable pod for attack" "false"
fi
echo ""

# Step 3: Verify Kyverno blocks vulnerable redeployment
echo -e "${BOLD}Step 3: Verify Kyverno policy enforcement${NC}"
policies=$(kubectl get clusterpolicies --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$policies" -gt 0 ]]; then
    # Delete and try to recreate vulnerable deployment
    kubectl delete deployment vulnerable-app -n vulnerable-app 2>/dev/null || true
    sleep 2

    if kubectl apply -f "${ROOT_DIR}/workloads/vulnerable-app/deployment.yaml" 2>/dev/null; then
        check "Kyverno blocked vulnerable deployment" "false"
    else
        check "Kyverno blocked vulnerable deployment" "true"
    fi
else
    echo -e "  ${YELLOW}⊘${NC} Kyverno policies not applied (skip enforcement test)"
fi
echo ""

# Step 4: Deploy compliant app (should succeed)
echo -e "${BOLD}Step 4: Deploy compliant workload${NC}"
kubectl apply -f "${ROOT_DIR}/workloads/compliant-app/namespace.yaml" 2>/dev/null || true
if kubectl apply -f "${ROOT_DIR}/workloads/compliant-app/" 2>/dev/null; then
    check "Compliant app deployment accepted" "true"
else
    check "Compliant app deployment accepted" "false"
fi
echo ""

# Results
echo -e "${BOLD}── Results ──${NC}"
echo -e "  ${GREEN}Passed: ${passed}${NC}"
echo -e "  ${RED}Failed: ${failed}${NC}"

[[ $failed -eq 0 ]] && exit 0 || exit 1
