#!/usr/bin/env bash
# ABOUTME: Tier 2 Observability & Delivery — Prometheus Stack, ArgoCD, External Secrets.
# ABOUTME: Sourced by install-tools.sh; provides install_tier2() and cleanup_tier2().
# ============================================================================
#
# TIER 2 — OBSERVABILITY & DELIVERY
#
# These tools provide monitoring, GitOps delivery, and secrets management.
# They depend on Tier 1 being installed (ServiceMonitor targets for Prometheus,
# policy enforcement for deployments).
#
# Install order within Tier 2:
#   [Prometheus Stack] → enables ServiceMonitors on Tier 1 tools
#   [ArgoCD]           → GitOps delivery engine
#   [External Secrets] → syncs secrets from Azure Key Vault
#
# TOOLS:
#   1. kube-prometheus-stack — Prometheus + Grafana + AlertManager
#   2. ArgoCD               — GitOps continuous delivery (CNCF Graduated)
#   3. External Secrets Operator — Secret sync from Key Vault
#
# STATUS: Stub — implementation in Phase 2
# ============================================================================

# Source common utilities if not already loaded
TIER2_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TIER2_LIB_DIR}/common.sh"

# ----------------------------------------------------------------------------
# TIER 2 NAMESPACES
# ----------------------------------------------------------------------------
TIER2_NAMESPACES=(monitoring argocd external-secrets)

# ----------------------------------------------------------------------------
# TIER 2 ORCHESTRATOR (STUB)
# ----------------------------------------------------------------------------
install_tier2() {
    echo -e "${BOLD}── Tier 2: Observability & Delivery ──${NC}"
    echo ""
    echo -e "${YELLOW}  Tier 2 tools not yet implemented.${NC}"
    echo -e "${YELLOW}  Planned: Prometheus Stack, ArgoCD, External Secrets Operator${NC}"
    echo ""
}

# ----------------------------------------------------------------------------
# TIER 2 SUMMARY
# ----------------------------------------------------------------------------
summary_tier2() {
    echo -e "${BOLD}  Tier 2 — Observability & Delivery${NC}"
    for ns in "${TIER2_NAMESPACES[@]}"; do
        print_namespace_status "${ns}"
    done
}

# ----------------------------------------------------------------------------
# TIER 2 CLEANUP (STUB)
# ----------------------------------------------------------------------------
cleanup_tier2() {
    echo -e "${YELLOW}Removing Tier 2 observability tools...${NC}"

    helm uninstall external-secrets -n external-secrets 2>/dev/null || true
    helm uninstall argocd -n argocd 2>/dev/null || true
    helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true

    for ns in "${TIER2_NAMESPACES[@]}"; do
        kubectl delete namespace "${ns}" --ignore-not-found 2>/dev/null || true
    done

    success "Tier 2 tools removed"
}

# ----------------------------------------------------------------------------
# TIER 2 VALIDATION (STUB)
# ----------------------------------------------------------------------------
validate_tier2() {
    local issues=0

    echo "Checking Tier 2 — Observability & Delivery..."

    for ns in "${TIER2_NAMESPACES[@]}"; do
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
