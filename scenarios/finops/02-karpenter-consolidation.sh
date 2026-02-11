#!/usr/bin/env bash
# ABOUTME: Demonstrates Karpenter node consolidation by deploying workloads and watching node selection.
# ABOUTME: Step 2 of the FinOps scenario — shows intelligent node right-sizing.
# ============================================================================
#
# STEP 2: KARPENTER NODE CONSOLIDATION
#
# This script:
#   1. Shows current Karpenter NodePools and AKSNodeClasses
#   2. Deploys workloads with specific resource requirements
#   3. Watches Karpenter select optimal VM SKUs
#   4. Demonstrates consolidation when workloads scale down
#
# PREREQUISITES:
#   - AKS cluster with Karpenter enabled (install-tools.sh --tier=4)
#   - NodePool CRDs applied
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

DEMO_NS="finops-demo"

# ----------------------------------------------------------------------------
# PREFLIGHT
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Step 2: Karpenter Node Consolidation ──${NC}"
echo ""

# Check Karpenter availability
info "Checking Karpenter availability..."
if kubectl get crd nodepools.karpenter.sh >/dev/null 2>&1; then
    success "Karpenter CRDs found"
else
    warn "Karpenter CRDs not found."
    warn "Enable with: ./scripts/install-tools.sh --tier=4"
    warn "Proceeding with informational content..."
fi
echo ""

# ----------------------------------------------------------------------------
# STEP 2a: SHOW CURRENT KARPENTER CONFIG
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Karpenter Configuration ──${NC}"
echo ""

info "NodePools (define what Karpenter can provision):"
kubectl get nodepools 2>/dev/null || info "No NodePools found"
echo ""

info "AKSNodeClasses (define Azure-specific node configuration):"
kubectl get aksnodeclasses 2>/dev/null || info "No AKSNodeClasses found"
echo ""

info "Karpenter controller status:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter 2>/dev/null || info "Karpenter controller not found in kube-system"
echo ""

info "How Karpenter selects nodes:"
echo "  1. Pods go Pending (insufficient capacity)"
echo "  2. Karpenter evaluates pod resource requirements"
echo "  3. Karpenter selects OPTIMAL VM SKU (not fixed-size VMSS)"
echo "  4. Node is provisioned in seconds (vs minutes for cluster-autoscaler)"
echo "  5. When utilization drops, Karpenter consolidates nodes"
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 2b: DEPLOY WORKLOADS TO TRIGGER SCALING
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Deploying Workloads for Node Scaling ──${NC}"
echo ""

kubectl create namespace "${DEMO_NS}" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

info "Deploying 5 replicas requesting 250m CPU / 256Mi each..."
echo "  This demonstrates Karpenter selecting a right-sized VM."
echo ""

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: finops-workload
  namespace: ${DEMO_NS}
  labels:
    app: finops-workload
    purpose: karpenter-demo
spec:
  replicas: 5
  selector:
    matchLabels:
      app: finops-workload
  template:
    metadata:
      labels:
        app: finops-workload
    spec:
      containers:
        - name: worker
          image: nginx:1.27
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          ports:
            - containerPort: 80
      # Tolerate Karpenter-provisioned nodes
      tolerations:
        - key: "karpenter.sh/disruption"
          operator: "Exists"
EOF

success "Deployed 5 replicas (total: 1250m CPU, 1280Mi memory requested)"
echo ""

info "Watching pod scheduling..."
kubectl get pods -n "${DEMO_NS}" -w --timeout=60 2>/dev/null &
WATCH_PID=$!
sleep 15
kill $WATCH_PID 2>/dev/null || true
echo ""

info "Current pod status:"
kubectl get pods -n "${DEMO_NS}" 2>/dev/null
echo ""

info "Node changes (Karpenter-provisioned nodes have karpenter.sh labels):"
kubectl get nodes --show-labels 2>/dev/null | grep -E "NAME|karpenter" || kubectl get nodes
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 2c: DEMONSTRATE CONSOLIDATION
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Node Consolidation ──${NC}"
echo ""

info "Scaling down to 1 replica (simulating low-traffic period)..."
kubectl scale deployment finops-workload -n "${DEMO_NS}" --replicas=1 2>/dev/null
echo ""

info "With consolidation enabled, Karpenter will:"
echo "  1. Detect that nodes are underutilized"
echo "  2. Move pods to more efficient nodes"
echo "  3. Terminate empty/underutilized nodes"
echo "  4. Save costs during off-peak hours"
echo ""

info "Current nodes after scale-down:"
kubectl get nodes 2>/dev/null
echo ""

info "Consolidation benefits:"
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │ Metric              │ Cluster Autoscaler │ Karpenter      │"
echo "  ├──────────────────────────────────────────────────────────┤"
echo "  │ VM Selection         │ Fixed size (VMSS)  │ Per-pod optimal│"
echo "  │ Scale-up Speed       │ 2-5 minutes        │ 30-60 seconds  │"
echo "  │ Consolidation        │ Manual/limited     │ Automatic      │"
echo "  │ Spot Support         │ VMSS spot pools    │ Native spot    │"
echo "  │ Bin-packing          │ Basic              │ Advanced       │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 2d: CLEANUP
# ----------------------------------------------------------------------------
info "Cleaning up FinOps workloads..."
kubectl delete namespace "${DEMO_NS}" --wait=false 2>/dev/null || true

success "Step 2 complete. Karpenter optimizes node selection and consolidation."
echo "  Next: Run 03-spot-workloads.sh to deploy to spot instances for cost savings."
