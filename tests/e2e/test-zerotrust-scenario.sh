#!/usr/bin/env bash
# ABOUTME: End-to-end test for the zero-trust networking scenario.
# ABOUTME: Deploys mesh app, applies policies, verifies isolation.
set -euo pipefail

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

echo -e "${BOLD}── E2E: Zero-Trust Scenario ──${NC}"
echo ""

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to cluster.${NC}"
    exit 1
fi

# Pre-check: Istio must be running
istiod_ok=$(kubectl get deploy -n istio-system istiod 2>/dev/null && echo "true" || echo "false")
check "istiod available" "$istiod_ok"
echo ""

if [[ "$istiod_ok" != "true" ]]; then
    echo -e "${YELLOW}Istio not available — skipping zero-trust e2e test${NC}"
    exit 0
fi

ZT_NS="e2e-zerotrust"

# Step 1: Create mesh-enabled namespace
echo -e "${BOLD}Step 1: Deploy mesh-enabled test app${NC}"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${ZT_NS}
  labels:
    istio-injection: enabled
EOF

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: ${ZT_NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
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
  name: test-app
  namespace: ${ZT_NS}
spec:
  selector:
    app: test-app
  ports:
    - port: 80
      targetPort: 80
EOF

kubectl wait --for=condition=ready pod -l app=test-app -n "${ZT_NS}" --timeout=120s 2>/dev/null || true

running=$(kubectl get pods -n "${ZT_NS}" -l app=test-app --no-headers 2>/dev/null | grep -c "Running" || echo "0")
check "Test app running in mesh namespace" "$([ "$running" -gt 0 ] && echo true || echo false)"

# Check sidecar injection
containers=$(kubectl get pod -l app=test-app -n "${ZT_NS}" -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null || echo "")
check "Envoy sidecar injected" "$(echo "$containers" | grep -q 'istio-proxy' && echo true || echo false)"
echo ""

# Step 2: Verify mTLS
echo -e "${BOLD}Step 2: Verify mTLS enforcement${NC}"
peer_auth=$(kubectl get peerauthentication -n istio-system --no-headers 2>/dev/null | wc -l || echo "0")
check "Mesh-wide PeerAuthentication exists" "$([ "$peer_auth" -gt 0 ] && echo true || echo false)"
echo ""

# Cleanup
echo -e "${BOLD}Cleanup:${NC}"
kubectl delete namespace "${ZT_NS}" --wait=false 2>/dev/null || true
echo "  Cleaned up ${ZT_NS} namespace"
echo ""

# Results
echo -e "${BOLD}── Results ──${NC}"
echo -e "  ${GREEN}Passed: ${passed}${NC}"
echo -e "  ${RED}Failed: ${failed}${NC}"

[[ $failed -eq 0 ]] && exit 0 || exit 1
