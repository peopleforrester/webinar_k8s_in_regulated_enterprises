#!/usr/bin/env bash
# ABOUTME: Tier 3 Platform & Registry — Istio, Crossplane, Harbor.
# ABOUTME: Sourced by install-tools.sh; provides install_tier3() and cleanup_tier3().
# ============================================================================
#
# TIER 3 — PLATFORM & REGISTRY
#
# These tools provide service mesh, infrastructure-as-code composition, and
# private container registry. They depend on Tier 2 for metrics collection
# and GitOps delivery.
#
# Install order within Tier 3:
#   [Istio base] → [Istio istiod] → mesh policies
#   [Crossplane] → [Azure Provider] → [ProviderConfig]
#   [Harbor]     → uses Azure Disk CSI PVCs
#
# TOOLS:
#   1. Istio      — Service mesh with mTLS (CNCF Graduated)
#   2. Crossplane — Infrastructure composition (CNCF Incubating)
#   3. Harbor     — Private container registry (CNCF Graduated)
#
# STATUS: Stub — implementation in Phase 3
# ============================================================================

# Source common utilities if not already loaded
TIER3_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TIER3_LIB_DIR}/common.sh"

# ----------------------------------------------------------------------------
# TIER 3 NAMESPACES
# ----------------------------------------------------------------------------
TIER3_NAMESPACES=(istio-system crossplane-system harbor)

# ----------------------------------------------------------------------------
# TIER 3 ORCHESTRATOR (STUB)
# ----------------------------------------------------------------------------
install_tier3() {
    echo -e "${BOLD}── Tier 3: Platform & Registry ──${NC}"
    echo ""
    echo -e "${YELLOW}  Tier 3 tools not yet implemented.${NC}"
    echo -e "${YELLOW}  Planned: Istio, Crossplane, Harbor${NC}"
    echo ""
}

# ----------------------------------------------------------------------------
# TIER 3 SUMMARY
# ----------------------------------------------------------------------------
summary_tier3() {
    echo -e "${BOLD}  Tier 3 — Platform & Registry${NC}"
    for ns in "${TIER3_NAMESPACES[@]}"; do
        print_namespace_status "${ns}"
    done
}

# ----------------------------------------------------------------------------
# TIER 3 CLEANUP (STUB)
# ----------------------------------------------------------------------------
# Istio cleanup: istiod first, then base (reverse install order).
# Crossplane: providers then core.
# Harbor: single release.
# ----------------------------------------------------------------------------
cleanup_tier3() {
    echo -e "${YELLOW}Removing Tier 3 platform tools...${NC}"

    # Harbor
    helm uninstall harbor -n harbor 2>/dev/null || true

    # Crossplane (providers then core)
    kubectl delete providers.pkg.crossplane.io --all 2>/dev/null || true
    helm uninstall crossplane -n crossplane-system 2>/dev/null || true

    # Istio (istiod then base)
    helm uninstall istiod -n istio-system 2>/dev/null || true
    helm uninstall istio-base -n istio-system 2>/dev/null || true

    for ns in "${TIER3_NAMESPACES[@]}"; do
        kubectl delete namespace "${ns}" --ignore-not-found 2>/dev/null || true
    done

    success "Tier 3 tools removed"
}

# ----------------------------------------------------------------------------
# TIER 3 VALIDATION (STUB)
# ----------------------------------------------------------------------------
validate_tier3() {
    local issues=0

    echo "Checking Tier 3 — Platform & Registry..."

    for ns in "${TIER3_NAMESPACES[@]}"; do
        local pod_count
        pod_count=$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$pod_count" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} ${ns}: ${pod_count} pods running"
        else
            echo -e "  ${YELLOW}⚠${NC} ${ns}: not deployed"
        fi
    done

    return $issues
}
