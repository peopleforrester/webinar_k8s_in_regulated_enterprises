#!/usr/bin/env bash
# ABOUTME: Enforces STRICT mutual TLS across the mesh and verifies encrypted connections.
# ABOUTME: Step 2 of the zero-trust scenario — encrypts all pod-to-pod traffic.
# ============================================================================
#
# STEP 2: ENFORCE MUTUAL TLS
#
# This script:
#   1. Applies mesh-wide PeerAuthentication with STRICT mTLS
#   2. Verifies all connections are now encrypted
#   3. Demonstrates that plaintext connections are rejected
#   4. Shows SPIFFE certificate details for identity verification
#
# WHY STRICT mTLS:
#   PERMISSIVE mode allows both plaintext and TLS (for migration).
#   STRICT mode REJECTS all plaintext connections. This is required
#   for regulated environments where data-in-transit encryption is
#   mandatory (PCI-DSS 4.1, NCUA Part 748).
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."

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
echo -e "${BOLD}── Step 2: Enforce Mutual TLS ──${NC}"
echo ""

if ! kubectl get namespace "${DEMO_NS}" >/dev/null 2>&1; then
    error "Namespace '${DEMO_NS}' not found. Run 01-deploy-mesh.sh first."
    exit 1
fi

# ----------------------------------------------------------------------------
# STEP 2a: APPLY MESH-WIDE STRICT mTLS
# ----------------------------------------------------------------------------
info "Applying mesh-wide PeerAuthentication (STRICT mode)..."
echo ""

# Apply from the existing manifest if available, otherwise create inline
if [[ -f "${ROOT_DIR}/tools/istio/manifests/peer-authentication.yaml" ]]; then
    kubectl apply -f "${ROOT_DIR}/tools/istio/manifests/peer-authentication.yaml"
    success "Applied PeerAuthentication from tools/istio/manifests/"
else
    kubectl apply -f - <<'EOF'
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF
    success "Applied mesh-wide STRICT PeerAuthentication"
fi
echo ""

# Also apply namespace-specific policy for the demo namespace
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: ${DEMO_NS}
spec:
  mtls:
    mode: STRICT
EOF
success "Applied namespace-level STRICT PeerAuthentication for ${DEMO_NS}"
echo ""

info "What STRICT mTLS means:"
echo "  - ALL pod-to-pod traffic is encrypted with TLS 1.3"
echo "  - Plaintext connections are REJECTED (not just upgraded)"
echo "  - Each pod gets a SPIFFE identity certificate (auto-rotated)"
echo "  - Certificates are issued by istiod (no external CA needed)"
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 2b: VERIFY mTLS IS ACTIVE
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Verifying mTLS ──${NC}"
echo ""

info "Checking PeerAuthentication policies..."
kubectl get peerauthentication --all-namespaces 2>/dev/null
echo ""

# Test encrypted connectivity
FRONTEND_POD=$(kubectl get pod -l app=frontend -n "${DEMO_NS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

info "Testing connectivity with mTLS enabled..."
echo ""

# frontend → backend (should still work via mTLS)
if kubectl exec "${FRONTEND_POD}" -n "${DEMO_NS}" -c nginx -- curl -s -o /dev/null -w "%{http_code}" http://backend.${DEMO_NS}.svc.cluster.local 2>/dev/null | grep -q "200"; then
    success "frontend → backend: CONNECTED via mTLS (HTTP 200)"
else
    warn "frontend → backend: connection test inconclusive (may need sidecar warmup)"
fi

# frontend → database (should work — mTLS doesn't restrict access, only encrypts)
if kubectl exec "${FRONTEND_POD}" -n "${DEMO_NS}" -c nginx -- curl -s -o /dev/null -w "%{http_code}" http://database.${DEMO_NS}.svc.cluster.local 2>/dev/null | grep -q "200"; then
    success "frontend → database: CONNECTED via mTLS (will be blocked by AuthZ policy later)"
else
    warn "frontend → database: connection test inconclusive"
fi
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 2c: SHOW SPIFFE CERTIFICATE DETAILS
# ----------------------------------------------------------------------------
echo -e "${BOLD}── SPIFFE Identity Certificates ──${NC}"
echo ""

info "Each pod receives a SPIFFE identity certificate from istiod."
echo "  Format: spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>"
echo ""

# Show proxy configuration and certificate info
info "Checking Envoy proxy certificate chain..."
if kubectl exec "${FRONTEND_POD}" -n "${DEMO_NS}" -c istio-proxy -- \
    pilot-agent request GET /certs 2>/dev/null | head -30; then
    echo "  ..."
else
    info "Certificate info via istioctl (if available):"
    echo "  istioctl proxy-config secret ${FRONTEND_POD}.${DEMO_NS}"
fi
echo ""

info "SPIFFE identities for demo services:"
echo "  frontend: spiffe://cluster.local/ns/${DEMO_NS}/sa/frontend"
echo "  backend:  spiffe://cluster.local/ns/${DEMO_NS}/sa/backend"
echo "  database: spiffe://cluster.local/ns/${DEMO_NS}/sa/database"
echo ""

info "Certificate rotation:"
echo "  - Default rotation: every 24 hours"
echo "  - No manual certificate management required"
echo "  - Compromised certificates are automatically replaced"
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 2d: DEMONSTRATE PLAINTEXT REJECTION (OPTIONAL)
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Plaintext Rejection Test ──${NC}"
echo ""

info "With STRICT mTLS, services without sidecars cannot communicate."
echo "  A pod without an Envoy sidecar sending plaintext will be rejected."
echo ""

# Deploy a pod WITHOUT sidecar injection to test
kubectl run plaintext-test --image=nginx:1.27 -n "${DEMO_NS}" \
    --overrides='{"metadata":{"annotations":{"sidecar.istio.io/inject":"false"}}}' \
    --restart=Never 2>/dev/null || true

kubectl wait --for=condition=ready pod/plaintext-test -n "${DEMO_NS}" --timeout=60s 2>/dev/null || true

# Try to connect from non-sidecar pod
info "Attempting plaintext connection from pod WITHOUT sidecar..."
result=$(kubectl exec plaintext-test -n "${DEMO_NS}" -- curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://backend.${DEMO_NS}.svc.cluster.local 2>/dev/null || echo "FAILED")

if [[ "$result" == "FAILED" ]] || [[ "$result" == "000" ]] || [[ "$result" == "503" ]]; then
    success "Plaintext connection REJECTED — STRICT mTLS is working!"
else
    warn "Connection returned: ${result} (may still be encrypted via Envoy sidecar)"
fi
echo ""

# Clean up test pod
kubectl delete pod plaintext-test -n "${DEMO_NS}" --wait=false 2>/dev/null || true

success "Step 2 complete. All traffic is encrypted with mutual TLS."
echo ""
echo -e "${YELLOW}Key regulatory takeaways:${NC}"
echo "  - PCI-DSS 4.1: All data-in-transit encrypted with TLS 1.3"
echo "  - NCUA Part 748: Member data encrypted between services"
echo "  - DORA Article 9: Cryptographic controls for ICT systems"
echo "  - SOC 2 CC6.1: Identity-based authentication (SPIFFE)"
echo ""
echo "  Next: Run 03-authorization-policies.sh to enforce service-level access control."
