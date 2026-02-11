#!/usr/bin/env bash
# ABOUTME: Tier 4 AKS-Managed — Karpenter NodePool CRDs (enabled via Terraform).
# ABOUTME: Sourced by install-tools.sh; provides install_tier4() and cleanup_tier4().
# ============================================================================
#
# TIER 4 — AKS-MANAGED SERVICES
#
# Karpenter on AKS is enabled via Terraform (node_provisioning_enabled).
# This tier applies NodePool and AKSNodeClass CRDs that tell Karpenter
# how to provision and manage nodes.
#
# Unlike Tiers 1-3 (Helm installs), Tier 4 uses kubectl apply for CRDs.
#
# TOOLS:
#   1. Karpenter — Node autoscaling via AKS Node Provisioning
#
# STATUS: Stub — implementation in Phase 4
# ============================================================================

# Source common utilities if not already loaded
TIER4_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TIER4_LIB_DIR}/common.sh"

# ----------------------------------------------------------------------------
# TIER 4 ORCHESTRATOR (STUB)
# ----------------------------------------------------------------------------
install_tier4() {
    echo -e "${BOLD}── Tier 4: AKS-Managed Services ──${NC}"
    echo ""
    echo -e "${YELLOW}  Tier 4 tools not yet implemented.${NC}"
    echo -e "${YELLOW}  Planned: Karpenter NodePool CRDs (requires Terraform changes)${NC}"
    echo ""
}

# ----------------------------------------------------------------------------
# TIER 4 SUMMARY
# ----------------------------------------------------------------------------
summary_tier4() {
    echo -e "${BOLD}  Tier 4 — AKS-Managed${NC}"

    local nodepools
    nodepools=$(kubectl get nodepools --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$nodepools" -gt 0 ]]; then
        echo -e "  ${GREEN}OK    Karpenter: ${nodepools} NodePool(s)${NC}"
    else
        echo -e "  ${YELLOW}SKIP  Karpenter: no NodePools found${NC}"
    fi
}

# ----------------------------------------------------------------------------
# TIER 4 CLEANUP (STUB)
# ----------------------------------------------------------------------------
cleanup_tier4() {
    echo -e "${YELLOW}Removing Tier 4 AKS-managed resources...${NC}"

    kubectl delete nodepools --all 2>/dev/null || true
    kubectl delete aksnodeclasses --all 2>/dev/null || true

    success "Tier 4 resources removed"
}

# ----------------------------------------------------------------------------
# TIER 4 VALIDATION (STUB)
# ----------------------------------------------------------------------------
validate_tier4() {
    local issues=0

    echo "Checking Tier 4 — AKS-Managed..."

    local nodepools
    nodepools=$(kubectl get nodepools --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$nodepools" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Karpenter: ${nodepools} NodePool(s) configured"
    else
        echo -e "  ${YELLOW}⚠${NC} Karpenter: no NodePools (requires Terraform enable)"
    fi

    return $issues
}
