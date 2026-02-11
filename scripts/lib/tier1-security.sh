#!/usr/bin/env bash
# ABOUTME: Tier 1 Security Core — Falco, Falcosidekick, Falco Talon, Kyverno, Trivy, Kubescape.
# ABOUTME: Sourced by install-tools.sh; provides install_tier1() and cleanup_tier1().
# ============================================================================
#
# TIER 1 — SECURITY CORE
#
# These tools form the security foundation of the platform. They must be
# installed first because higher tiers (monitoring, GitOps, mesh) depend on
# the security controls being in place.
#
# Install order within Tier 1:
#   [Falco] → [Falcosidekick] → [Falco Talon]   (dependency chain)
#   [Kyverno]  [Trivy]  [Kubescape]              (independent)
#
# TOOLS:
#   1. Falco         — Runtime threat detection via eBPF (CNCF Graduated)
#   2. Falcosidekick — Alert routing to 50+ destinations
#   3. Falco Talon   — Automated response engine for Falco events
#   4. Kyverno       — Kubernetes-native policy engine (CNCF Incubating)
#   5. Trivy Operator — Continuous vulnerability scanning
#   6. Kubescape     — Compliance scanning (NSA, SOC2, MITRE)
#
# ============================================================================

# Source common utilities if not already loaded
TIER1_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TIER1_LIB_DIR}/common.sh"

# ----------------------------------------------------------------------------
# HELM REPOSITORIES FOR TIER 1
# ----------------------------------------------------------------------------
setup_tier1_repos() {
    helm_repo_add falcosecurity https://falcosecurity.github.io/charts
    helm_repo_add kyverno https://kyverno.github.io/kyverno/
    helm_repo_add aqua https://aquasecurity.github.io/helm-charts/
    helm_repo_add kubescape https://kubescape.github.io/helm-charts/
    helm repo update
    success "Tier 1 Helm repos configured"
}

# ----------------------------------------------------------------------------
# INSTALL FUNCTIONS (one per tool)
# ----------------------------------------------------------------------------

install_falco() {
    progress "Installing Falco (runtime threat detection)..."
    helm_install falco falcosecurity/falco \
        falco \
        "${TOOLS_DIR}/falco/values.yaml" \
        5m
    verify_install "falco" "Falco" || true
    echo ""
}

install_falcosidekick() {
    progress "Installing Falcosidekick (alert forwarding)..."
    helm_install falcosidekick falcosecurity/falcosidekick \
        falco \
        "${TOOLS_DIR}/falcosidekick/values.yaml" \
        3m
    verify_install "falco" "Falcosidekick" || true
    echo ""
}

install_falco_talon() {
    progress "Installing Falco Talon (automated response)..."
    helm_install falco-talon falcosecurity/falco-talon \
        falco \
        "${TOOLS_DIR}/falco-talon/values.yaml" \
        3m
    verify_install "falco" "Falco Talon" || true
    echo ""
}

install_kyverno() {
    progress "Installing Kyverno (policy engine)..."
    helm_install kyverno kyverno/kyverno \
        kyverno \
        "${TOOLS_DIR}/kyverno/values.yaml" \
        5m
    verify_install "kyverno" "Kyverno" || true
    echo ""
}

install_trivy() {
    progress "Installing Trivy Operator (vulnerability scanning)..."
    helm_install trivy-operator aqua/trivy-operator \
        trivy-system \
        "${TOOLS_DIR}/trivy/values.yaml" \
        5m
    verify_install "trivy-system" "Trivy Operator" || true
    echo ""
}

install_kubescape() {
    progress "Installing Kubescape (compliance scanning)..."
    helm_install kubescape kubescape/kubescape-operator \
        kubescape \
        "${TOOLS_DIR}/kubescape/values.yaml" \
        5m
    verify_install "kubescape" "Kubescape" || true
    echo ""
}

# ----------------------------------------------------------------------------
# TIER 1 ORCHESTRATOR
# ----------------------------------------------------------------------------
# Installs all Tier 1 tools in dependency order.
# Sets up progress tracking for 7 steps (1 repo setup + 6 tools).
# ----------------------------------------------------------------------------
install_tier1() {
    echo -e "${BOLD}── Tier 1: Security Core ──${NC}"
    echo ""

    set_total_steps 7

    progress "Setting up Helm repositories..."
    setup_tier1_repos
    echo ""

    install_falco
    install_falcosidekick
    install_falco_talon
    install_kyverno
    install_trivy
    install_kubescape
}

# ----------------------------------------------------------------------------
# TIER 1 SUMMARY
# ----------------------------------------------------------------------------
# Prints pod status for all Tier 1 namespaces.
# ----------------------------------------------------------------------------
summary_tier1() {
    echo -e "${BOLD}  Tier 1 — Security Core${NC}"
    for ns in falco kyverno trivy-system kubescape; do
        print_namespace_status "${ns}"
    done
}

# ----------------------------------------------------------------------------
# TIER 1 CLEANUP
# ----------------------------------------------------------------------------
# Uninstalls all Tier 1 Helm releases and deletes namespaces.
# Reverse order of install to respect dependencies.
# ----------------------------------------------------------------------------
cleanup_tier1() {
    echo -e "${YELLOW}Removing Tier 1 security tools...${NC}"

    helm uninstall kubescape -n kubescape 2>/dev/null || true
    helm uninstall trivy-operator -n trivy-system 2>/dev/null || true
    helm uninstall kyverno -n kyverno 2>/dev/null || true
    helm uninstall falco-talon -n falco 2>/dev/null || true
    helm uninstall falcosidekick -n falco 2>/dev/null || true
    helm uninstall falco -n falco 2>/dev/null || true

    kubectl delete namespace kubescape --ignore-not-found 2>/dev/null || true
    kubectl delete namespace trivy-system --ignore-not-found 2>/dev/null || true
    kubectl delete namespace kyverno --ignore-not-found 2>/dev/null || true
    kubectl delete namespace falco --ignore-not-found 2>/dev/null || true

    success "Tier 1 security tools removed"
}

# ----------------------------------------------------------------------------
# TIER 1 VALIDATION
# ----------------------------------------------------------------------------
# Quick health checks for Tier 1 tools. Returns number of issues found.
# ----------------------------------------------------------------------------
validate_tier1() {
    local issues=0

    echo "Checking Tier 1 — Security Core..."

    # Kyverno
    local kyverno_pods
    kyverno_pods=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$kyverno_pods" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Kyverno: ${kyverno_pods} pods running"
    else
        echo -e "  ${RED}✗${NC} Kyverno: not running"
        issues=$((issues + 1))
    fi

    # Falco
    local falco_pods
    falco_pods=$(kubectl get pods -n falco -l app.kubernetes.io/name=falco --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$falco_pods" -gt 0 ]]; then
        local nodes
        nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
        echo -e "  ${GREEN}✓${NC} Falco: ${falco_pods}/${nodes} nodes covered"
    else
        echo -e "  ${RED}✗${NC} Falco: not running"
        issues=$((issues + 1))
    fi

    # Falcosidekick
    local sidekick_pods
    sidekick_pods=$(kubectl get pods -n falco -l app.kubernetes.io/name=falcosidekick --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$sidekick_pods" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Falcosidekick: ${sidekick_pods} pods running"
    else
        echo -e "  ${YELLOW}⚠${NC} Falcosidekick: not running"
    fi

    # Falco Talon
    local talon_pods
    talon_pods=$(kubectl get pods -n falco -l app.kubernetes.io/name=falco-talon --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$talon_pods" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Falco Talon: ${talon_pods} pods running"
    else
        echo -e "  ${YELLOW}⚠${NC} Falco Talon: not running"
    fi

    # Trivy
    local trivy_pods
    trivy_pods=$(kubectl get pods -n trivy-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$trivy_pods" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Trivy Operator: ${trivy_pods} pods running"
    else
        echo -e "  ${RED}✗${NC} Trivy Operator: not running"
        issues=$((issues + 1))
    fi

    # Kubescape
    local kubescape_pods
    kubescape_pods=$(kubectl get pods -n kubescape --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$kubescape_pods" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Kubescape: ${kubescape_pods} pods running"
    else
        echo -e "  ${YELLOW}⚠${NC} Kubescape: not running"
    fi

    return $issues
}
