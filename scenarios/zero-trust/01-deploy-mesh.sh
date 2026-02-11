#!/usr/bin/env bash
# ABOUTME: Deploys a multi-service application with Istio sidecar injection enabled.
# ABOUTME: Step 1 of the zero-trust scenario — sets up the service mesh foundation.
# ============================================================================
#
# STEP 1: DEPLOY MESH-ENABLED APPLICATION
#
# This script:
#   1. Creates a namespace with Istio sidecar injection enabled
#   2. Deploys a three-tier application (frontend → backend → database)
#   3. Verifies Envoy sidecars are injected into all pods
#   4. Tests baseline connectivity between services
#
# PREREQUISITES:
#   - AKS cluster with Istio installed (install-tools.sh --tier=3)
#   - istiod running in istio-system namespace
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."

# Terminal colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}  ℹ ${NC} $*"; }
success() { echo -e "${GREEN}  ✓ ${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠ ${NC} $*"; }
error()   { echo -e "${RED}  ✗ ${NC} $*"; }

DEMO_NS="zero-trust-demo"

# ----------------------------------------------------------------------------
# PREFLIGHT
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Step 1: Deploy Mesh-Enabled Application ──${NC}"
echo ""

info "Checking Istio availability..."
if ! kubectl get deploy -n istio-system istiod >/dev/null 2>&1; then
    error "Istio not found. Run: ./scripts/install-tools.sh --tier=3"
    exit 1
fi
success "istiod found in istio-system namespace"
echo ""

# ----------------------------------------------------------------------------
# STEP 1a: CREATE NAMESPACE WITH SIDECAR INJECTION
# ----------------------------------------------------------------------------
info "Creating namespace '${DEMO_NS}' with Istio sidecar injection..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${DEMO_NS}
  labels:
    istio-injection: enabled
    purpose: zero-trust-demo
EOF
success "Namespace '${DEMO_NS}' created with istio-injection: enabled"
echo ""

# ----------------------------------------------------------------------------
# STEP 1b: DEPLOY THREE-TIER APPLICATION
# ----------------------------------------------------------------------------
info "Deploying multi-service application..."
echo "  frontend → backend → database"
echo ""

# Frontend service (accepts external traffic, calls backend)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: frontend
  namespace: zero-trust-demo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: zero-trust-demo
  labels:
    app: frontend
    tier: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        tier: web
    spec:
      serviceAccountName: frontend
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: zero-trust-demo
spec:
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 80
EOF

# Backend service (accepts from frontend, calls database)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend
  namespace: zero-trust-demo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: zero-trust-demo
  labels:
    app: backend
    tier: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        tier: api
    spec:
      serviceAccountName: backend
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: zero-trust-demo
spec:
  selector:
    app: backend
  ports:
    - port: 80
      targetPort: 80
EOF

# Database service (accepts only from backend)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: database
  namespace: zero-trust-demo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
  namespace: zero-trust-demo
  labels:
    app: database
    tier: data
spec:
  replicas: 1
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
        tier: data
    spec:
      serviceAccountName: database
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: database
  namespace: zero-trust-demo
spec:
  selector:
    app: database
  ports:
    - port: 80
      targetPort: 80
EOF

success "All three services deployed"
echo ""

# ----------------------------------------------------------------------------
# STEP 1c: WAIT FOR PODS WITH SIDECARS
# ----------------------------------------------------------------------------
info "Waiting for pods to be ready (with Envoy sidecars)..."
kubectl wait --for=condition=ready pod -l app=frontend -n "${DEMO_NS}" --timeout=120s 2>/dev/null || warn "frontend may take a moment"
kubectl wait --for=condition=ready pod -l app=backend -n "${DEMO_NS}" --timeout=120s 2>/dev/null || warn "backend may take a moment"
kubectl wait --for=condition=ready pod -l app=database -n "${DEMO_NS}" --timeout=120s 2>/dev/null || warn "database may take a moment"
echo ""

# Verify sidecar injection
info "Verifying Envoy sidecar injection..."
for svc in frontend backend database; do
    containers=$(kubectl get pod -l app="${svc}" -n "${DEMO_NS}" -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null || echo "")
    if echo "$containers" | grep -q "istio-proxy"; then
        success "${svc}: Envoy sidecar injected (containers: ${containers})"
    else
        warn "${svc}: sidecar NOT found (containers: ${containers})"
    fi
done
echo ""

# ----------------------------------------------------------------------------
# STEP 1d: TEST BASELINE CONNECTIVITY
# ----------------------------------------------------------------------------
info "Testing baseline connectivity (before policies)..."
echo ""

FRONTEND_POD=$(kubectl get pod -l app=frontend -n "${DEMO_NS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# frontend → backend (should work)
if kubectl exec "${FRONTEND_POD}" -n "${DEMO_NS}" -c nginx -- curl -s -o /dev/null -w "%{http_code}" http://backend.${DEMO_NS}.svc.cluster.local 2>/dev/null | grep -q "200"; then
    success "frontend → backend: CONNECTED (HTTP 200)"
else
    warn "frontend → backend: connection test inconclusive"
fi

# frontend → database (should work BEFORE policies)
if kubectl exec "${FRONTEND_POD}" -n "${DEMO_NS}" -c nginx -- curl -s -o /dev/null -w "%{http_code}" http://database.${DEMO_NS}.svc.cluster.local 2>/dev/null | grep -q "200"; then
    success "frontend → database: CONNECTED (HTTP 200) — will be BLOCKED after policies"
else
    warn "frontend → database: connection test inconclusive"
fi

echo ""

# ----------------------------------------------------------------------------
# STEP 1e: DISPLAY STATUS
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Deployed Resources ──${NC}"
echo ""
kubectl get pods -n "${DEMO_NS}" -o wide 2>/dev/null
echo ""
kubectl get svc -n "${DEMO_NS}" 2>/dev/null
echo ""

success "Step 1 complete. Three-tier app deployed with Envoy sidecars."
echo "  All services can currently reach each other (no restrictions)."
echo "  Next: Run 02-enforce-mtls.sh to enable mutual TLS encryption."
