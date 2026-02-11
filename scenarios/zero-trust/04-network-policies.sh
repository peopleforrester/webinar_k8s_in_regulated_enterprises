#!/usr/bin/env bash
# ABOUTME: Applies Kubernetes NetworkPolicies for L3/L4 pod isolation as defense-in-depth.
# ABOUTME: Step 4 of the zero-trust scenario — network segmentation below the mesh.
# ============================================================================
#
# STEP 4: KUBERNETES NETWORK POLICIES
#
# This script adds Kubernetes NetworkPolicies as a second layer of defense
# below the Istio AuthorizationPolicies:
#
#   Layer 7 (Istio): SPIFFE identity, HTTP method/path control
#   Layer 3/4 (NetworkPolicy): Pod IP, port, namespace isolation
#
# WHY BOTH LAYERS:
#   - Defense in depth: if Istio is bypassed, NetworkPolicies still block
#   - NetworkPolicies are enforced by the CNI (Cilium on AKS), not Envoy
#   - Independent control planes reduce single-point-of-failure risk
#   - Regulatory requirement: multiple independent security controls
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
echo -e "${BOLD}── Step 4: Kubernetes Network Policies ──${NC}"
echo ""

if ! kubectl get namespace "${DEMO_NS}" >/dev/null 2>&1; then
    error "Namespace '${DEMO_NS}' not found. Run 01-deploy-mesh.sh first."
    exit 1
fi

# ----------------------------------------------------------------------------
# STEP 4a: DEFAULT-DENY NETWORK POLICY
# ----------------------------------------------------------------------------
info "Applying default-deny NetworkPolicy (blocks all ingress and egress)..."
echo ""

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ${DEMO_NS}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
EOF

success "Default-deny NetworkPolicy applied"
echo ""

# ----------------------------------------------------------------------------
# STEP 4b: ALLOW DNS EGRESS (REQUIRED FOR SERVICE DISCOVERY)
# ----------------------------------------------------------------------------
info "Allowing DNS egress to kube-system (required for service resolution)..."
echo ""

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: ${DEMO_NS}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
      to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
EOF

success "DNS egress allowed for all pods"
echo ""

# ----------------------------------------------------------------------------
# STEP 4c: ALLOW ISTIO CONTROL PLANE COMMUNICATION
# ----------------------------------------------------------------------------
info "Allowing Istio control plane communication..."
echo ""

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-istio-control-plane
  namespace: ${DEMO_NS}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # Allow Envoy to communicate with istiod for config and certs
    - ports:
        - protocol: TCP
          port: 15012
        - protocol: TCP
          port: 15010
        - protocol: TCP
          port: 15014
      to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
EOF

success "Istio control plane egress allowed"
echo ""

# ----------------------------------------------------------------------------
# STEP 4d: ALLOW SERVICE GRAPH (FRONTEND → BACKEND → DATABASE)
# ----------------------------------------------------------------------------
info "Applying service graph NetworkPolicies..."
echo ""

# Frontend: accepts inbound, can reach backend
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-policy
  namespace: ${DEMO_NS}
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: backend
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 15008
EOF

success "frontend → backend: ALLOWED at L3/L4"

# Backend: accepts from frontend, can reach database
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-ingress-policy
  namespace: ${DEMO_NS}
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 15008
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-egress-policy
  namespace: ${DEMO_NS}
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: database
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 15008
EOF

success "backend accepts from frontend, reaches database: ALLOWED at L3/L4"

# Database: accepts only from backend
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-policy
  namespace: ${DEMO_NS}
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: backend
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 15008
EOF

success "database accepts from backend only: ALLOWED at L3/L4"
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 4e: SHOW ALL NETWORK POLICIES
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Active Network Policies ──${NC}"
echo ""
kubectl get networkpolicies -n "${DEMO_NS}" 2>/dev/null
echo ""

# ----------------------------------------------------------------------------
# STEP 4f: VERIFY ISOLATION
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Verifying Network Isolation ──${NC}"
echo ""

FRONTEND_POD=$(kubectl get pod -l app=frontend -n "${DEMO_NS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# Test: frontend → database should be blocked at L3/L4 AND L7
info "Test: frontend → database (blocked by NetworkPolicy AND AuthorizationPolicy)..."
result=$(kubectl exec "${FRONTEND_POD}" -n "${DEMO_NS}" -c nginx -- curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://database.${DEMO_NS}.svc.cluster.local 2>/dev/null || echo "000")
if [[ "$result" == "000" || "$result" == "403" ]]; then
    success "frontend → database: BLOCKED at network level (${result})"
else
    warn "frontend → database: returned ${result} (expected timeout or 403)"
fi

# Test: frontend → external should be blocked (no egress rule for external)
info "Test: frontend → external internet (blocked by default-deny egress)..."
result=$(kubectl exec "${FRONTEND_POD}" -n "${DEMO_NS}" -c nginx -- curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://httpbin.org/status/200 2>/dev/null || echo "000")
if [[ "$result" == "000" ]]; then
    success "frontend → internet: BLOCKED (no egress route)"
else
    warn "frontend → internet: returned ${result} (expected timeout)"
fi

echo ""
pause

# ----------------------------------------------------------------------------
# STEP 4g: DEFENSE-IN-DEPTH SUMMARY
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Defense-in-Depth Summary ──${NC}"
echo ""

echo "  ┌──────────────────────────────────────────────────────┐"
echo "  │ Layer         │ Control           │ Enforced By      │"
echo "  ├──────────────────────────────────────────────────────┤"
echo "  │ L7 Identity   │ AuthorizationPolicy│ Envoy (Istio)   │"
echo "  │ mTLS          │ PeerAuthentication │ Envoy (Istio)   │"
echo "  │ L3/L4 Network │ NetworkPolicy      │ Cilium (CNI)    │"
echo "  │ Runtime       │ Falco rules        │ Falco agent     │"
echo "  └──────────────────────────────────────────────────────┘"
echo ""
echo "  If ANY single layer is bypassed, the others still protect."
echo "  This is the essence of zero-trust: never trust, always verify."
echo ""

success "Step 4 complete. Four independent security layers are active."
echo ""
echo -e "${YELLOW}Key regulatory takeaways:${NC}"
echo "  - FFIEC Defense in Depth: Four independent security layers"
echo "  - NIST 800-207: Microsegmentation at network and application layers"
echo "  - DORA Article 9: Network segmentation for ICT risk management"
echo "  - PCI-DSS 1.3: Restricting inbound and outbound traffic"
echo "  - SOC 2 CC6.6: Network security controls at multiple layers"
echo ""
echo "  Run: ./run-demo.sh --cleanup to remove all demo resources."
