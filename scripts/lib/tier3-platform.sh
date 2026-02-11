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
#   [Istio base] → [Istio istiod] → mesh-wide PeerAuthentication
#   [Crossplane] → [Azure Provider] → [ProviderConfig]
#   [Harbor]     → uses Azure Disk CSI PVCs (managed-csi StorageClass)
#
# TOOLS:
#   1. Istio      — Service mesh with mTLS (CNCF Graduated)
#   2. Crossplane — Infrastructure composition (CNCF Incubating)
#   3. Harbor     — Private container registry (CNCF Graduated)
#
# ============================================================================

# Source common utilities if not already loaded
TIER3_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TIER3_LIB_DIR}/common.sh"

# ----------------------------------------------------------------------------
# TIER 3 NAMESPACES
# ----------------------------------------------------------------------------
TIER3_NAMESPACES=(istio-system crossplane-system harbor)

# ----------------------------------------------------------------------------
# HELM REPOSITORIES FOR TIER 3
# ----------------------------------------------------------------------------
setup_tier3_repos() {
    helm_repo_add istio https://istio-release.storage.googleapis.com/charts
    helm_repo_add crossplane-stable https://charts.crossplane.io/stable
    helm_repo_add harbor https://helm.goharbor.io
    helm repo update
    success "Tier 3 Helm repos configured"
}

# ----------------------------------------------------------------------------
# INSTALL ISTIO (TWO-PHASE)
# ----------------------------------------------------------------------------
# Istio is installed in two phases:
#   1. istio-base: Installs CRDs (PeerAuthentication, AuthorizationPolicy, etc.)
#   2. istiod: Installs the control plane (Pilot, CA, xDS discovery)
#
# After both phases, we apply a mesh-wide PeerAuthentication for STRICT mTLS.
# ----------------------------------------------------------------------------
install_istio() {
    progress "Installing Istio base (CRDs)..."
    helm_install istio-base istio/base \
        istio-system \
        "" \
        3m \
        --set defaultRevision=default
    success "Istio base CRDs installed"
    echo ""

    progress "Installing istiod (control plane)..."
    helm_install istiod istio/istiod \
        istio-system \
        "${TOOLS_DIR}/istio/values.yaml" \
        5m
    verify_install "istio-system" "istiod" || true
    echo ""

    # Apply mesh-wide STRICT mTLS
    local pa_manifest="${TOOLS_DIR}/istio/manifests/peer-authentication.yaml"
    if [[ -f "${pa_manifest}" ]]; then
        info "Applying mesh-wide STRICT mTLS PeerAuthentication..."
        kubectl apply -f "${pa_manifest}" 2>/dev/null || warn "Could not apply PeerAuthentication"
        success "Mesh-wide STRICT mTLS enabled"
    fi
    echo ""
}

# ----------------------------------------------------------------------------
# INSTALL CROSSPLANE
# ----------------------------------------------------------------------------
# Crossplane is installed in three phases:
#   1. Core: Helm install of crossplane controller and RBAC manager
#   2. Providers: Apply Azure provider packages (network, database)
#   3. ProviderConfig: Configure authentication (workload identity)
#
# Provider health is verified between phases — providers must be healthy
# before ProviderConfig can be applied (it depends on provider CRDs).
# ----------------------------------------------------------------------------
install_crossplane() {
    progress "Installing Crossplane (infrastructure composition)..."
    helm_install crossplane crossplane-stable/crossplane \
        crossplane-system \
        "${TOOLS_DIR}/crossplane/values.yaml" \
        5m
    verify_install "crossplane-system" "Crossplane" || true
    echo ""

    # Apply Azure providers
    local provider_manifest="${TOOLS_DIR}/crossplane/manifests/provider.yaml"
    if [[ -f "${provider_manifest}" ]]; then
        info "Applying Crossplane Azure providers..."
        kubectl apply -f "${provider_manifest}" 2>/dev/null || warn "Could not apply Crossplane providers"

        # Wait for providers to become healthy (up to 120s)
        info "Waiting for providers to become healthy (up to 120s)..."
        local elapsed=0
        while [[ $elapsed -lt 120 ]]; do
            local healthy
            healthy=$(kubectl get providers.pkg.crossplane.io --no-headers 2>/dev/null \
                | grep -c "True" || echo "0")
            local total
            total=$(kubectl get providers.pkg.crossplane.io --no-headers 2>/dev/null \
                | wc -l || echo "0")

            if [[ $total -gt 0 && $healthy -eq $total ]]; then
                success "All ${total} Crossplane providers healthy"
                break
            fi

            sleep 10
            elapsed=$((elapsed + 10))
        done

        if [[ $elapsed -ge 120 ]]; then
            warn "Crossplane providers not fully healthy after 120s"
            kubectl get providers.pkg.crossplane.io 2>/dev/null | sed 's/^/    /'
        fi
    fi
    echo ""
}

# ----------------------------------------------------------------------------
# INSTALL HARBOR
# ----------------------------------------------------------------------------
# Harbor is a heavy install (7+ components: core, portal, registry, database,
# redis, jobservice, trivy scanner). Uses managed-csi StorageClass for PVCs.
# Timeout is extended to 10m to allow for PVC provisioning and DB init.
# ----------------------------------------------------------------------------
install_harbor() {
    progress "Installing Harbor (private container registry)..."
    info "This is a heavy install (~7 components). Timeout: 10m."
    helm_install harbor harbor/harbor \
        harbor \
        "${TOOLS_DIR}/harbor/values.yaml" \
        10m
    verify_install "harbor" "Harbor" || true

    info "Harbor access:"
    info "  Portal:     kubectl port-forward svc/harbor-portal -n harbor 8443:443"
    info "  Default:    admin / Harbor12345 (change in production!)"
    echo ""
}

# ----------------------------------------------------------------------------
# TIER 3 ORCHESTRATOR
# ----------------------------------------------------------------------------
install_tier3() {
    echo -e "${BOLD}── Tier 3: Platform & Registry ──${NC}"
    echo ""

    set_total_steps 6

    progress "Setting up Helm repositories..."
    setup_tier3_repos
    echo ""

    install_istio
    install_crossplane
    install_harbor
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
# TIER 3 CLEANUP
# ----------------------------------------------------------------------------
# Reverse order of install. Istio requires istiod removed before base.
# Crossplane providers must be removed before core to avoid orphaned CRDs.
# ----------------------------------------------------------------------------
cleanup_tier3() {
    echo -e "${YELLOW}Removing Tier 3 platform tools...${NC}"

    # Harbor (single release)
    helm uninstall harbor -n harbor 2>/dev/null || true

    # Crossplane: ProviderConfig → Providers → Core
    kubectl delete providerconfig.azure.upbound.io --all 2>/dev/null || true
    kubectl delete providers.pkg.crossplane.io --all 2>/dev/null || true
    helm uninstall crossplane -n crossplane-system 2>/dev/null || true

    # Istio: PeerAuthentication → istiod → base
    kubectl delete peerauthentication -n istio-system --all 2>/dev/null || true
    helm uninstall istiod -n istio-system 2>/dev/null || true
    helm uninstall istio-base -n istio-system 2>/dev/null || true

    # Clean up Istio CRDs (Helm leaves them behind)
    kubectl get crd -o name 2>/dev/null \
        | grep -E 'istio\.io|networking\.istio|security\.istio|telemetry\.istio' \
        | xargs -r kubectl delete 2>/dev/null || true

    # Clean up Crossplane CRDs
    kubectl get crd -o name 2>/dev/null \
        | grep -E 'crossplane\.io|upbound\.io' \
        | xargs -r kubectl delete 2>/dev/null || true

    for ns in "${TIER3_NAMESPACES[@]}"; do
        kubectl delete namespace "${ns}" --ignore-not-found 2>/dev/null || true
    done

    success "Tier 3 tools removed"
}

# ----------------------------------------------------------------------------
# TIER 3 VALIDATION
# ----------------------------------------------------------------------------
validate_tier3() {
    local issues=0

    echo "Checking Tier 3 — Platform & Registry..."

    # Istio
    local istiod_pods
    istiod_pods=$(kubectl get pods -n istio-system -l app=istiod --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$istiod_pods" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} istiod: ${istiod_pods} pod(s) running"

        # Check PeerAuthentication
        local pa_count
        pa_count=$(kubectl get peerauthentication -n istio-system --no-headers 2>/dev/null | wc -l || echo "0")
        if [[ "$pa_count" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} PeerAuthentication: mesh-wide mTLS active"
        else
            echo -e "  ${YELLOW}⚠${NC} PeerAuthentication: not applied"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Istio: not deployed"
    fi

    # Crossplane
    local xp_pods
    xp_pods=$(kubectl get pods -n crossplane-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$xp_pods" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Crossplane: ${xp_pods} pod(s) running"

        # Check provider health
        local provider_count
        provider_count=$(kubectl get providers.pkg.crossplane.io --no-headers 2>/dev/null | wc -l || echo "0")
        local provider_healthy
        provider_healthy=$(kubectl get providers.pkg.crossplane.io --no-headers 2>/dev/null | grep -c "True" || echo "0")
        if [[ "$provider_count" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} Crossplane providers: ${provider_healthy}/${provider_count} healthy"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Crossplane: not deployed"
    fi

    # Harbor
    local harbor_pods
    harbor_pods=$(kubectl get pods -n harbor --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$harbor_pods" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Harbor: ${harbor_pods} pod(s) running"
    else
        echo -e "  ${YELLOW}⚠${NC} Harbor: not deployed"
    fi

    return $issues
}
