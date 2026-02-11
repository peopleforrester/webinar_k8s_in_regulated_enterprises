#!/usr/bin/env bash
# ABOUTME: Orchestrates the full FinOps cost optimization scenario with pauses for narration.
# ABOUTME: Runs all three steps demonstrating resource visibility and cost optimization.
# ============================================================================
#
# FINOPS COST OPTIMIZATION SCENARIO — FULL DEMO ORCHESTRATOR
#
# TIMING (approximate):
#   - Introduction: 2 minutes
#   - Step 1 (Baseline costs): 5 minutes
#   - Step 2 (Karpenter consolidation): 7 minutes
#   - Step 3 (Spot workloads): 5 minutes
#   - Summary: 2 minutes
#   Total: ~21 minutes
#
# USAGE:
#   ./run-demo.sh              # Full interactive demo
#   ./run-demo.sh --step=1     # Run only step 1
#   ./run-demo.sh --step=2     # Run only step 2
#   ./run-demo.sh --step=3     # Run only step 3
#   ./run-demo.sh --cleanup    # Remove all demo resources
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "  $*"; }
success() { echo -e "${GREEN}  ✓ ${NC} $*"; }

pause() {
    echo ""
    echo -e "${BLUE}  Press Enter to continue...${NC}"
    read -r
}

# ----------------------------------------------------------------------------
# ARGUMENT PARSING
# ----------------------------------------------------------------------------
STEP=""
CLEANUP=false

for arg in "$@"; do
    case "$arg" in
        --step=*)  STEP="${arg#--step=}" ;;
        --cleanup) CLEANUP=true ;;
        --help|-h)
            echo "Usage: run-demo.sh [--step=1|2|3] [--cleanup]"
            exit 0
            ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# ----------------------------------------------------------------------------
# CLEANUP
# ----------------------------------------------------------------------------
if [[ "$CLEANUP" == "true" ]]; then
    echo -e "${BOLD}── FinOps Demo Cleanup ──${NC}"
    echo ""
    kubectl delete namespace finops-demo --wait=false 2>/dev/null || true
    kubectl delete namespace finops-spot-demo --wait=false 2>/dev/null || true
    success "FinOps demo resources cleaned up"
    exit 0
fi

# ----------------------------------------------------------------------------
# INTRODUCTION
# ----------------------------------------------------------------------------
if [[ -z "$STEP" || "$STEP" == "1" ]]; then
    echo -e "${BOLD}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  FinOps Cost Optimization Demo            ║${NC}"
    echo -e "${BOLD}║  Karpenter + Prometheus + Grafana          ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo "This demo shows three cost optimization techniques:"
    echo ""
    echo "  1. ${GREEN}Baseline${NC}       — Measure resource utilization and waste"
    echo "  2. ${GREEN}Consolidation${NC}  — Karpenter right-sizes nodes automatically"
    echo "  3. ${GREEN}Spot Instances${NC} — 78-85% savings on fault-tolerant workloads"
    echo ""
    echo -e "${YELLOW}FinOps principle:${NC} Every dollar of cloud spend should be"
    echo "  traceable, optimized, and aligned with business value."
    echo ""

    if [[ -z "$STEP" ]]; then
        pause
    fi
fi

# Steps
if [[ -z "$STEP" || "$STEP" == "1" ]]; then
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  STEP 1: Resource Utilization Baseline${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if [[ -z "$STEP" ]]; then pause; fi
    "${SCRIPT_DIR}/01-baseline-costs.sh"
    if [[ -z "$STEP" ]]; then pause; fi
fi

if [[ -z "$STEP" || "$STEP" == "2" ]]; then
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  STEP 2: Karpenter Node Consolidation${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if [[ -z "$STEP" ]]; then pause; fi
    "${SCRIPT_DIR}/02-karpenter-consolidation.sh"
    if [[ -z "$STEP" ]]; then pause; fi
fi

if [[ -z "$STEP" || "$STEP" == "3" ]]; then
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  STEP 3: Spot Instance Workloads${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if [[ -z "$STEP" ]]; then pause; fi
    "${SCRIPT_DIR}/03-spot-workloads.sh"
    if [[ -z "$STEP" ]]; then pause; fi
fi

# Summary
if [[ -z "$STEP" ]]; then
    echo -e "${BOLD}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  DEMO COMPLETE                            ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}FinOps Summary:${NC}"
    echo ""
    echo "  1. MEASURE  — Prometheus + Grafana show utilization vs waste"
    echo "  2. OPTIMIZE — Karpenter selects right-sized VMs per workload"
    echo "  3. SAVE     — Spot instances cut 78-85% on eligible workloads"
    echo ""
    echo -e "${YELLOW}Typical savings: 30-50% overall compute costs${NC}"
    echo ""
    echo "Cleanup: ./run-demo.sh --cleanup"
fi
