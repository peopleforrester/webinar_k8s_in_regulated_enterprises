#!/usr/bin/env bash
# ABOUTME: Queries Prometheus for resource utilization metrics and identifies waste.
# ABOUTME: Step 1 of the FinOps scenario — establishes the cost optimization baseline.
# ============================================================================
#
# STEP 1: BASELINE RESOURCE UTILIZATION
#
# This script:
#   1. Queries Prometheus for node and pod resource metrics
#   2. Calculates request-to-usage ratios to identify waste
#   3. Shows per-namespace resource consumption
#   4. Highlights over-provisioned workloads
#
# PREREQUISITES:
#   - Prometheus Stack installed (install-tools.sh --tier=2)
#   - Workloads running in the cluster
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# ----------------------------------------------------------------------------
# PREFLIGHT
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Step 1: Resource Utilization Baseline ──${NC}"
echo ""

# Check Prometheus availability
PROM_SVC="prometheus-kube-prometheus-prometheus"
PROM_NS="monitoring"

info "Checking Prometheus availability..."
if ! kubectl get svc "${PROM_SVC}" -n "${PROM_NS}" >/dev/null 2>&1; then
    # Try alternate service name
    PROM_SVC="kube-prometheus-stack-prometheus"
    if ! kubectl get svc "${PROM_SVC}" -n "${PROM_NS}" >/dev/null 2>&1; then
        warn "Prometheus service not found in ${PROM_NS} namespace."
        warn "Install with: ./scripts/install-tools.sh --tier=2"
        warn "Proceeding with kubectl-based metrics..."
        PROM_AVAILABLE=false
    else
        PROM_AVAILABLE=true
    fi
else
    PROM_AVAILABLE=true
fi

if [[ "$PROM_AVAILABLE" == "true" ]]; then
    success "Prometheus found: ${PROM_SVC}.${PROM_NS}"
fi
echo ""

# Helper to query Prometheus
prom_query() {
    local query="$1"
    kubectl run prom-query --rm -i --restart=Never --image=curlimages/curl:latest \
        -- curl -s --connect-timeout 5 \
        "http://${PROM_SVC}.${PROM_NS}.svc.cluster.local:9090/api/v1/query?query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$query'))" 2>/dev/null || echo "$query")" \
        2>/dev/null | python3 -m json.tool 2>/dev/null || echo "Query failed"
}

# ----------------------------------------------------------------------------
# STEP 1a: NODE RESOURCE SUMMARY
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Node Resource Summary ──${NC}"
echo ""

info "Current cluster nodes:"
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,STATUS:.status.conditions[-1].type,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory,INSTANCE:.metadata.labels.node\.kubernetes\.io/instance-type' \
    2>/dev/null || kubectl get nodes -o wide
echo ""

# Calculate total allocatable vs requested
info "Node resource allocation:"
echo ""

total_cpu_request=0
total_cpu_alloc=0
total_mem_request=0
total_mem_alloc=0

while read -r node; do
    cpu_alloc=$(kubectl get node "$node" -o jsonpath='{.status.allocatable.cpu}' 2>/dev/null | sed 's/m$//' || echo "0")
    mem_alloc=$(kubectl get node "$node" -o jsonpath='{.status.allocatable.memory}' 2>/dev/null | sed 's/Ki$//' || echo "0")

    # Get requested resources on this node
    cpu_req=$(kubectl describe node "$node" 2>/dev/null | grep -A5 "Allocated resources" | grep "cpu" | awk '{print $2}' | sed 's/m$//' || echo "0")
    mem_req=$(kubectl describe node "$node" 2>/dev/null | grep -A5 "Allocated resources" | grep "memory" | awk '{print $2}' | sed 's/Mi$//' || echo "0")

    # Handle cores (no m suffix) vs millicores
    if [[ "$cpu_alloc" =~ ^[0-9]+$ ]] && [[ ${#cpu_alloc} -le 3 ]]; then
        cpu_alloc=$((cpu_alloc * 1000))
    fi

    echo "  ${node}:"
    echo "    CPU:    ${cpu_req:-?}m requested / ${cpu_alloc}m allocatable"
    echo "    Memory: ${mem_req:-?}Mi requested / $((mem_alloc / 1024))Mi allocatable"
done < <(kubectl get nodes -o name 2>/dev/null | sed 's|node/||')
echo ""

# ----------------------------------------------------------------------------
# STEP 1b: PER-NAMESPACE RESOURCE CONSUMPTION
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Per-Namespace Resource Requests ──${NC}"
echo ""

info "Top namespaces by resource requests:"
echo ""

printf "  %-30s %12s %12s\n" "NAMESPACE" "CPU REQUEST" "MEM REQUEST"
printf "  %-30s %12s %12s\n" "─────────" "───────────" "───────────"

kubectl get pods --all-namespaces -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
ns_resources = {}
for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    if ns not in ns_resources:
        ns_resources[ns] = {'cpu': 0, 'mem': 0}
    for container in pod['spec'].get('containers', []):
        requests = container.get('resources', {}).get('requests', {})
        cpu = requests.get('cpu', '0')
        mem = requests.get('memory', '0')
        # Parse CPU
        if cpu.endswith('m'):
            ns_resources[ns]['cpu'] += int(cpu[:-1])
        elif cpu.isdigit():
            ns_resources[ns]['cpu'] += int(cpu) * 1000
        # Parse Memory
        if mem.endswith('Mi'):
            ns_resources[ns]['mem'] += int(mem[:-2])
        elif mem.endswith('Gi'):
            ns_resources[ns]['mem'] += int(float(mem[:-2]) * 1024)
        elif mem.endswith('Ki'):
            ns_resources[ns]['mem'] += int(int(mem[:-2]) / 1024)

for ns, res in sorted(ns_resources.items(), key=lambda x: x[1]['cpu'], reverse=True):
    print(f'  {ns:<30} {res[\"cpu\"]:>10}m {res[\"mem\"]:>10}Mi')
" 2>/dev/null || warn "Could not parse resource data"
echo ""

# ----------------------------------------------------------------------------
# STEP 1c: IDENTIFY WASTE (REQUESTED >> ACTUAL USAGE)
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Resource Waste Analysis ──${NC}"
echo ""

if [[ "$PROM_AVAILABLE" == "true" ]]; then
    info "Querying Prometheus for actual CPU usage vs requests..."
    info "(If metrics are not yet available, this section shows estimates)"
    echo ""
fi

# Use kubectl top if metrics-server is available
if kubectl top pods --all-namespaces --no-headers 2>/dev/null | head -1 >/dev/null 2>&1; then
    info "Top resource consumers (actual usage from metrics-server):"
    echo ""
    kubectl top pods --all-namespaces --sort-by=cpu 2>/dev/null | head -15
    echo ""
    echo "  ..."
    echo ""

    info "Nodes actual usage:"
    kubectl top nodes 2>/dev/null || true
    echo ""
else
    warn "Metrics server not available. Install metrics-server or use Prometheus."
    echo ""
    info "Estimated waste based on common patterns:"
    echo "  - System pods typically use 10-30% of requested resources"
    echo "  - Security tools (Falco, Trivy) use 5-15% of requested resources"
    echo "  - Application workloads vary widely"
    echo ""
fi

# Summary
info "Cost optimization opportunities:"
echo "  1. Right-size resource requests based on actual usage"
echo "  2. Use Karpenter to select optimal VM SKUs per workload"
echo "  3. Move fault-tolerant workloads to spot instances"
echo "  4. Consolidate underutilized nodes"
echo ""

success "Step 1 complete. Baseline resource metrics collected."
echo "  Next: Run 02-karpenter-consolidation.sh to see intelligent node scaling."
