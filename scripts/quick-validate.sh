#!/bin/bash
# ABOUTME: Quick validation script for existing AKS cluster with security tools
# ABOUTME: Use this to verify tools are working without full infrastructure deploy

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           QUICK VALIDATION - AKS Regulated Demo               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

#######################################
# 1. Cluster Connection
#######################################
echo "1. Checking cluster connection..."
if kubectl cluster-info &>/dev/null; then
    CLUSTER=$(kubectl config current-context)
    success "Connected to: $CLUSTER"
else
    error "Not connected to a cluster. Run: az aks get-credentials ..."
    exit 1
fi

#######################################
# 2. Kyverno Status
#######################################
echo ""
echo "2. Checking Kyverno..."
KYVERNO_PODS=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | grep -c "Running" || echo "0")
KYVERNO_POLICIES=$(kubectl get cpol --no-headers 2>/dev/null | wc -l || echo "0")

if [ "$KYVERNO_PODS" -gt 0 ]; then
    success "Kyverno: $KYVERNO_PODS pods running"
    echo "   Policies:"
    kubectl get cpol --no-headers 2>/dev/null | awk '{print "   - " $1 " (" $2 ")"}'
else
    warn "Kyverno not installed or not running"
fi

#######################################
# 3. Falco Status
#######################################
echo ""
echo "3. Checking Falco..."
FALCO_PODS=$(kubectl get pods -n falco --no-headers 2>/dev/null | grep -c "Running" || echo "0")
NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")

if [ "$FALCO_PODS" -gt 0 ]; then
    success "Falco: $FALCO_PODS/$NODES nodes covered (DaemonSet)"
    echo "   Recent alerts:"
    kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=5 2>/dev/null | grep -i "warning\|notice\|critical" | head -3 || echo "   (no recent alerts)"
else
    warn "Falco not installed or not running"
fi

#######################################
# 4. Kubescape Status
#######################################
echo ""
echo "4. Checking Kubescape..."
KUBESCAPE_PODS=$(kubectl get pods -n kubescape --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "$KUBESCAPE_PODS" -gt 0 ]; then
    success "Kubescape Operator: $KUBESCAPE_PODS pods running"
else
    warn "Kubescape Operator not installed"
fi

if command -v kubescape &>/dev/null; then
    success "Kubescape CLI available"
else
    warn "Kubescape CLI not installed locally"
fi

#######################################
# 5. Demo Workloads
#######################################
echo ""
echo "5. Checking demo workloads..."
if kubectl get namespace demo &>/dev/null; then
    DEMO_PODS=$(kubectl get pods -n demo --no-headers 2>/dev/null | wc -l || echo "0")
    success "Demo namespace exists with $DEMO_PODS pods"
    kubectl get pods -n demo --no-headers 2>/dev/null | awk '{print "   - " $1 " (" $3 ")"}'
else
    warn "Demo namespace not found. Deploy with: kubectl apply -f demo-workloads/compliant-app/"
fi

#######################################
# 6. Quick Policy Test
#######################################
echo ""
echo "6. Quick policy test (attempting to create privileged pod)..."
TEST_RESULT=$(kubectl run test-privileged --image=nginx --restart=Never \
    --overrides='{"spec":{"containers":[{"name":"nginx","image":"nginx","securityContext":{"privileged":true}}]}}' \
    --dry-run=server -o yaml 2>&1 || true)

if echo "$TEST_RESULT" | grep -qi "blocked\|denied\|disallow"; then
    success "Kyverno correctly blocked privileged pod"
else
    warn "Privileged pod was not blocked - check Kyverno policies"
fi

#######################################
# Summary
#######################################
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "VALIDATION SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo ""

ISSUES=0

[ "$KYVERNO_PODS" -eq 0 ] && { error "Kyverno not running"; ISSUES=$((ISSUES+1)); } || success "Kyverno OK"
[ "$FALCO_PODS" -eq 0 ] && { error "Falco not running"; ISSUES=$((ISSUES+1)); } || success "Falco OK"
[ "$KUBESCAPE_PODS" -eq 0 ] && { warn "Kubescape Operator not running"; } || success "Kubescape OK"

echo ""
if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}All core security tools are operational!${NC}"
    echo ""
    echo "Ready for demo. Suggested next steps:"
    echo "  1. Run attack simulation:  ./attack-simulation/run-attack.sh"
    echo "  2. Watch Falco logs:       kubectl logs -n falco -l app.kubernetes.io/name=falco -f"
    echo "  3. Run compliance scan:    kubescape scan framework cis-v1.12.0"
else
    echo -e "${YELLOW}$ISSUES issues found. Please address before demo.${NC}"
fi
echo ""
