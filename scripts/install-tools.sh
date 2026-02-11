#!/usr/bin/env bash
# ABOUTME: Installs the complete CNCF tool stack via Helm charts in dependency tiers.
# ABOUTME: Supports tiered install (--tier=1|2|3|4|all) for incremental deployment.
# ============================================================================
#
# PURPOSE:
#   This script deploys a comprehensive cloud-native platform stack organized
#   into dependency tiers:
#
#   TIER 1 — Security Core (Falco, Falcosidekick, Falco Talon, Kyverno,
#            Trivy Operator, Kubescape)
#   TIER 2 — Observability & Delivery (Prometheus Stack, ArgoCD,
#            External Secrets Operator)
#   TIER 3 — Platform & Registry (Istio, Crossplane, Harbor)
#   TIER 4 — AKS-Managed (Karpenter NodePool CRDs)
#
# PREREQUISITES:
#   - kubectl configured and connected to target cluster
#   - Helm 3.x installed
#   - Cluster should have at least 4GB memory available (Tier 1 only)
#   - Additional resources for higher tiers
#
# USAGE:
#   ./install-tools.sh              # Install all tiers (default)
#   ./install-tools.sh --tier=1     # Install Tier 1 only (security core)
#   ./install-tools.sh --tier=2     # Install Tier 2 only (observability)
#   ./install-tools.sh --tier=3     # Install Tier 3 only (platform)
#   ./install-tools.sh --tier=4     # Install Tier 4 only (AKS-managed)
#   ./install-tools.sh --tier=1,2   # Install specific tiers
#   ./install-tools.sh --help       # Show usage
#
# INSTALL ORDER:
#   Tier 1 → Tier 2 → Tier 3 → Tier 4
#   Each tier depends on the previous tier's services.
#
# ESTIMATED TIME:
#   Tier 1: 5-10 minutes
#   Tier 2: 5-8 minutes
#   Tier 3: 8-12 minutes
#   Tier 4: 1-2 minutes (CRD apply only)
#   All:    20-30 minutes
#
# NAMESPACE STRATEGY:
#   Each tool gets its own namespace for security isolation, resource
#   quota management, and easier cleanup/debugging.
#
# ============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# SOURCE SHARED LIBRARIES
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tier1-security.sh"
source "${SCRIPT_DIR}/lib/tier2-observability.sh"
source "${SCRIPT_DIR}/lib/tier3-platform.sh"
source "${SCRIPT_DIR}/lib/tier4-aks-managed.sh"

# ----------------------------------------------------------------------------
# ARGUMENT PARSING
# ----------------------------------------------------------------------------
INSTALL_TIERS="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --tier=*)
            INSTALL_TIERS="${1#--tier=}"
            shift
            ;;
        --tier)
            INSTALL_TIERS="${2:-all}"
            shift 2
            ;;
        -h|--help)
            echo "Usage: install-tools.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --tier=TIERS  Install specific tiers (1, 2, 3, 4, all)"
            echo "                Comma-separated for multiple: --tier=1,2"
            echo "                Default: all"
            echo "  -h, --help    Show this help"
            echo ""
            echo "Tiers:"
            echo "  1  Security Core     Falco, Falcosidekick, Falco Talon, Kyverno, Trivy, Kubescape"
            echo "  2  Observability     Prometheus Stack, ArgoCD, External Secrets"
            echo "  3  Platform          Istio, Crossplane, Harbor"
            echo "  4  AKS-Managed       Karpenter NodePool CRDs"
            echo "  all                  All tiers in order (default)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1 (use --help for usage)"
            exit 1
            ;;
    esac
done

# Convert tier specification to array
should_install_tier() {
    local tier="$1"
    if [[ "${INSTALL_TIERS}" == "all" ]]; then
        return 0
    fi
    # Check if the requested tier is in the comma-separated list
    echo ",${INSTALL_TIERS}," | grep -q ",${tier},"
}

# ----------------------------------------------------------------------------
# HEADER
# ----------------------------------------------------------------------------
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Installing CNCF Tool Stack${NC}"
if [[ "${INSTALL_TIERS}" != "all" ]]; then
    echo -e "${BOLD}  Tiers: ${INSTALL_TIERS}${NC}"
fi
echo -e "${BOLD}========================================${NC}"
echo ""

# ----------------------------------------------------------------------------
# PREREQUISITE CHECKS
# ----------------------------------------------------------------------------
check_prerequisites
echo ""

# ----------------------------------------------------------------------------
# TIERED INSTALLATION
# ----------------------------------------------------------------------------

if should_install_tier 1; then
    install_tier1
fi

if should_install_tier 2; then
    install_tier2
fi

if should_install_tier 3; then
    install_tier3
fi

if should_install_tier 4; then
    install_tier4
fi

# ----------------------------------------------------------------------------
# INSTALLATION SUMMARY
# ----------------------------------------------------------------------------
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Installation Summary${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

if should_install_tier 1; then
    summary_tier1
    echo ""
fi

if should_install_tier 2; then
    summary_tier2
    echo ""
fi

if should_install_tier 3; then
    summary_tier3
    echo ""
fi

if should_install_tier 4; then
    summary_tier4
    echo ""
fi

# ----------------------------------------------------------------------------
# FINAL STATUS
# ----------------------------------------------------------------------------
if has_failures; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  INSTALLATION INCOMPLETE${NC}"
    echo -e "${RED}  Failed: $(get_failures)${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  Check pod logs:  kubectl logs -n <namespace> <pod-name>"
    echo "  Check events:    kubectl get events -n <namespace> --sort-by=.lastTimestamp"
    echo "  See:             docs/TROUBLESHOOTING.md"
    exit 1
else
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  All tools installed successfully${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  Deploy demo workloads:  kubectl apply -f workloads/vulnerable-app/"
    echo "  Run attack demo:        ./scenarios/attack-detect-prevent/run-demo.sh"
    echo "  Validate install:       ./scripts/quick-validate.sh"
fi
