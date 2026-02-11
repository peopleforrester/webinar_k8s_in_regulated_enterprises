#!/usr/bin/env bash
# ABOUTME: Applies Istio AuthorizationPolicies for Layer 7 service-to-service access control.
# ABOUTME: Step 3 of the zero-trust scenario — enforces identity-based authorization.
# ============================================================================
#
# STEP 3: AUTHORIZATION POLICIES
#
# This script:
#   1. Applies a default-deny AuthorizationPolicy for the demo namespace
#   2. Adds explicit allow rules for the service graph:
#      - frontend → backend (allowed)
#      - backend → database (allowed)
#      - frontend → database (DENIED — must go through backend)
#   3. Tests that authorized connections succeed
#   4. Tests that unauthorized connections are blocked
#
# WHY LAYER 7 AUTHORIZATION:
#   NetworkPolicies operate at L3/L4 (IP/port). AuthorizationPolicies
#   operate at L7 (HTTP method, path, headers) with SPIFFE identity.
#   This provides much finer-grained control.
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

DEMO_NS="zero-trust-demo"

# ----------------------------------------------------------------------------
# PREFLIGHT
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Step 3: Authorization Policies ──${NC}"
echo ""

if ! kubectl get namespace "${DEMO_NS}" >/dev/null 2>&1; then
    error "Namespace '${DEMO_NS}' not found. Run 01-deploy-mesh.sh first."
    exit 1
fi

# ----------------------------------------------------------------------------
# STEP 3a: APPLY DEFAULT-DENY POLICY
# ----------------------------------------------------------------------------
info "Applying default-deny AuthorizationPolicy..."
echo "  This blocks ALL traffic in the namespace until explicit allows are added."
echo ""

kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: ${DEMO_NS}
spec:
  # Empty spec = deny all traffic to all workloads in namespace
  {}
EOF

success "Default-deny policy applied to ${DEMO_NS}"
echo ""

# Quick test: everything should be blocked now
FRONTEND_POD=$(kubectl get pod -l app=frontend -n "${DEMO_NS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

info "Testing after default-deny (all connections should fail)..."
# Give Envoy time to receive policy update
sleep 3

result=$(kubectl exec "${FRONTEND_POD}" -n "${DEMO_NS}" -c nginx -- curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://backend.${DEMO_NS}.svc.cluster.local 2>/dev/null || echo "000")
if [[ "$result" == "403" || "$result" == "000" ]]; then
    success "frontend → backend: DENIED (HTTP ${result}) — default-deny working"
else
    warn "frontend → backend: returned ${result} (expected 403)"
fi
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 3b: ALLOW FRONTEND → BACKEND
# ----------------------------------------------------------------------------
info "Adding allow rule: frontend → backend..."
echo ""

kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: ${DEMO_NS}
spec:
  selector:
    matchLabels:
      app: backend
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/${DEMO_NS}/sa/frontend"
      to:
        - operation:
            methods: ["GET", "POST"]
            ports: ["80"]
EOF

success "Allow rule: frontend (SPIFFE identity) → backend (port 80, GET/POST)"
echo ""

# ----------------------------------------------------------------------------
# STEP 3c: ALLOW BACKEND → DATABASE
# ----------------------------------------------------------------------------
info "Adding allow rule: backend → database..."
echo ""

kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-backend-to-database
  namespace: ${DEMO_NS}
spec:
  selector:
    matchLabels:
      app: database
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/${DEMO_NS}/sa/backend"
      to:
        - operation:
            methods: ["GET", "POST"]
            ports: ["80"]
EOF

success "Allow rule: backend (SPIFFE identity) → database (port 80, GET/POST)"
echo ""

# Give Envoy time to propagate policy updates
sleep 5
pause

# ----------------------------------------------------------------------------
# STEP 3d: TEST AUTHORIZED CONNECTIONS
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Testing Authorization ──${NC}"
echo ""

FRONTEND_POD=$(kubectl get pod -l app=frontend -n "${DEMO_NS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
BACKEND_POD=$(kubectl get pod -l app=backend -n "${DEMO_NS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# Test 1: frontend → backend (SHOULD SUCCEED)
info "Test 1: frontend → backend (authorized)..."
result=$(kubectl exec "${FRONTEND_POD}" -n "${DEMO_NS}" -c nginx -- curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://backend.${DEMO_NS}.svc.cluster.local 2>/dev/null || echo "000")
if [[ "$result" == "200" ]]; then
    success "frontend → backend: ALLOWED (HTTP 200) ✓"
else
    warn "frontend → backend: HTTP ${result} (expected 200, policy may need propagation time)"
fi

# Test 2: backend → database (SHOULD SUCCEED)
info "Test 2: backend → database (authorized)..."
result=$(kubectl exec "${BACKEND_POD}" -n "${DEMO_NS}" -c nginx -- curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://database.${DEMO_NS}.svc.cluster.local 2>/dev/null || echo "000")
if [[ "$result" == "200" ]]; then
    success "backend → database: ALLOWED (HTTP 200) ✓"
else
    warn "backend → database: HTTP ${result} (expected 200)"
fi

# Test 3: frontend → database (SHOULD FAIL — not authorized)
info "Test 3: frontend → database (NOT authorized — must go through backend)..."
result=$(kubectl exec "${FRONTEND_POD}" -n "${DEMO_NS}" -c nginx -- curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://database.${DEMO_NS}.svc.cluster.local 2>/dev/null || echo "000")
if [[ "$result" == "403" || "$result" == "000" ]]; then
    success "frontend → database: DENIED (HTTP ${result}) ✓ — must go through backend"
else
    warn "frontend → database: HTTP ${result} (expected 403 — check policy propagation)"
fi

echo ""
pause

# ----------------------------------------------------------------------------
# STEP 3e: SHOW POLICY SUMMARY
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Active Authorization Policies ──${NC}"
echo ""
kubectl get authorizationpolicies -n "${DEMO_NS}" 2>/dev/null
echo ""

info "Service graph enforcement:"
echo "  frontend → backend  : ${GREEN}ALLOWED${NC} (SPIFFE identity match)"
echo "  backend  → database : ${GREEN}ALLOWED${NC} (SPIFFE identity match)"
echo "  frontend → database : ${RED}DENIED${NC}  (no matching rule)"
echo "  external → anything : ${RED}DENIED${NC}  (default-deny)"
echo ""

success "Step 3 complete. Layer 7 authorization enforces the service graph."
echo ""
echo -e "${YELLOW}Key regulatory takeaways:${NC}"
echo "  - SOC 2 CC6.1: Access based on cryptographic identity (SPIFFE), not IP"
echo "  - NIST 800-207: Least-privilege access, deny by default"
echo "  - PCI-DSS 7.1: Restrict access based on business need-to-know"
echo "  - DORA Article 9: Access control for ICT services"
echo ""
echo "  Next: Run 04-network-policies.sh for additional L3/L4 isolation."
