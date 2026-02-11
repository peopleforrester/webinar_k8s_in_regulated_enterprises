#!/usr/bin/env bash
# ABOUTME: Deploys fault-tolerant workloads to Karpenter spot NodePool for cost savings.
# ABOUTME: Step 3 of the FinOps scenario — demonstrates spot instance optimization.
# ============================================================================
#
# STEP 3: SPOT INSTANCE WORKLOADS
#
# This script:
#   1. Shows the Karpenter spot NodePool configuration
#   2. Deploys fault-tolerant workloads targeting spot instances
#   3. Demonstrates cost savings potential (up to 90%)
#   4. Shows graceful handling of spot evictions
#
# SPOT INSTANCE STRATEGY:
#   Spot instances are surplus Azure capacity available at up to 90%
#   discount. They can be evicted with 30 seconds notice. Suitable for:
#   - Batch processing and CI/CD runners
#   - Dev/test workloads
#   - Stateless web workers with load balancers
#   - Data processing pipelines
#
#   NOT suitable for:
#   - Databases and stateful workloads
#   - Production-critical single-replica services
#   - Workloads without graceful shutdown handling
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

pause() {
    echo ""
    echo -e "${BLUE}  Press Enter to continue...${NC}"
    read -r
}

DEMO_NS="finops-spot-demo"

# ----------------------------------------------------------------------------
# PREFLIGHT
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Step 3: Spot Instance Workloads ──${NC}"
echo ""

# ----------------------------------------------------------------------------
# STEP 3a: SHOW SPOT NODEPOOL CONFIGURATION
# ----------------------------------------------------------------------------
info "Karpenter spot NodePool configuration:"
echo ""

if kubectl get nodepool spot-workloads 2>/dev/null; then
    echo ""
    kubectl get nodepool spot-workloads -o yaml 2>/dev/null | head -30
else
    info "No spot NodePool found. Here's what it looks like:"
    echo ""
    echo -e "${CYAN}  apiVersion: karpenter.sh/v1"
    echo "  kind: NodePool"
    echo "  metadata:"
    echo "    name: spot-workloads"
    echo "  spec:"
    echo "    template:"
    echo "      spec:"
    echo "        requirements:"
    echo "          - key: karpenter.sh/capacity-type"
    echo "            operator: In"
    echo "            values: [\"spot\"]"
    echo "          - key: kubernetes.io/arch"
    echo "            operator: In"
    echo "            values: [\"amd64\"]"
    echo "        nodeClassRef:"
    echo "          group: karpenter.azure.com"
    echo "          kind: AKSNodeClass"
    echo "          name: default"
    echo "    disruption:"
    echo "      consolidationPolicy: WhenEmptyOrUnderutilized"
    echo -e "      consolidateAfter: 30s${NC}"
fi
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 3b: DEPLOY SPOT-TOLERANT WORKLOAD
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Deploying Spot-Tolerant Workload ──${NC}"
echo ""

kubectl create namespace "${DEMO_NS}" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

info "Deploying batch processing workload targeting spot instances..."
echo ""

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-processor
  namespace: ${DEMO_NS}
  labels:
    app: batch-processor
    workload-type: spot-tolerant
spec:
  replicas: 3
  selector:
    matchLabels:
      app: batch-processor
  template:
    metadata:
      labels:
        app: batch-processor
        workload-type: spot-tolerant
    spec:
      # Target spot instances via node affinity
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: karpenter.sh/capacity-type
                    operator: In
                    values:
                      - spot
      # Tolerate spot instance disruptions
      tolerations:
        - key: "karpenter.sh/disruption"
          operator: "Exists"
        - key: "kubernetes.azure.com/scalesetpriority"
          value: "spot"
          effect: "NoSchedule"
      # Graceful shutdown handling
      terminationGracePeriodSeconds: 30
      containers:
        - name: worker
          image: nginx:1.27
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
          # Lifecycle hook for graceful eviction handling
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 5 && nginx -s quit"]
EOF

success "Deployed 3 spot-tolerant batch processor replicas"
echo ""

info "Pod scheduling status:"
kubectl get pods -n "${DEMO_NS}" -o wide 2>/dev/null
echo ""

# Check which nodes pods landed on
info "Node placement:"
kubectl get pods -n "${DEMO_NS}" -o custom-columns=\
'POD:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase' 2>/dev/null
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 3c: COST SAVINGS ANALYSIS
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Cost Savings Analysis ──${NC}"
echo ""

info "Azure Spot Instance pricing comparison (typical East US 2):"
echo ""
echo "  ┌──────────────────────────────────────────────────────────────┐"
echo "  │ VM Size          │ On-Demand/mo │ Spot/mo    │ Savings      │"
echo "  ├──────────────────────────────────────────────────────────────┤"
echo "  │ Standard_D2s_v3  │ ~\$70         │ ~\$10-15   │ 78-85%       │"
echo "  │ Standard_D4s_v3  │ ~\$140        │ ~\$20-30   │ 78-85%       │"
echo "  │ Standard_D8s_v3  │ ~\$280        │ ~\$40-55   │ 80-85%       │"
echo "  │ Standard_D16s_v3 │ ~\$560        │ ~\$80-110  │ 80-85%       │"
echo "  └──────────────────────────────────────────────────────────────┘"
echo ""
echo "  Note: Spot prices vary by region, time, and demand."
echo "        Karpenter diversifies across VM families to reduce eviction risk."
echo ""

info "Best practices for spot workloads:"
echo "  1. Multiple replicas across different VM families"
echo "  2. Graceful shutdown handling (terminationGracePeriodSeconds)"
echo "  3. Pod Disruption Budgets to limit concurrent evictions"
echo "  4. Avoid spot for databases, state stores, and single-replica services"
echo "  5. Use on-demand for minimum baseline, spot for burst capacity"
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 3d: MIXED ON-DEMAND + SPOT STRATEGY
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Mixed Instance Strategy ──${NC}"
echo ""

info "Recommended production strategy:"
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │ Workload Type     │ Instance Type  │ NodePool           │"
echo "  ├──────────────────────────────────────────────────────────┤"
echo "  │ System (CoreDNS)  │ On-Demand      │ system (AKS mgd)   │"
echo "  │ Databases/State   │ On-Demand      │ default (Karpenter) │"
echo "  │ Prod API servers  │ On-Demand      │ default (Karpenter) │"
echo "  │ Batch processing  │ Spot           │ spot (Karpenter)    │"
echo "  │ Dev/Test          │ Spot           │ spot (Karpenter)    │"
echo "  │ CI/CD runners     │ Spot           │ spot (Karpenter)    │"
echo "  │ ML training       │ Spot           │ spot (Karpenter)    │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "  Typical savings: 30-50% overall compute costs"
echo "  (spot for 40-60% of non-critical workloads)"
echo ""

# ----------------------------------------------------------------------------
# STEP 3e: CLEANUP
# ----------------------------------------------------------------------------
info "Cleaning up spot demo resources..."
kubectl delete namespace "${DEMO_NS}" --wait=false 2>/dev/null || true

success "Step 3 complete. Spot instances provide significant cost savings."
echo ""
echo -e "${YELLOW}Key regulatory takeaways:${NC}"
echo "  - DORA Article 11: Optimize capacity through intelligent scaling"
echo "  - NCUA fiduciary duty: Demonstrate cost-conscious infrastructure"
echo "  - Spot instances for non-critical workloads, on-demand for SLAs"
echo "  - Karpenter automates the on-demand/spot split per workload needs"
echo ""
echo "  Run: ./run-demo.sh --cleanup to remove all demo resources."
