#!/usr/bin/env bash
# ABOUTME: Tier 4 AKS-Managed — Karpenter Node Autoprovisioning via Azure CLI + CRDs.
# ABOUTME: Sourced by install-tools.sh; provides install_tier4() and cleanup_tier4().
# ============================================================================
#
# TIER 4 — AKS-MANAGED SERVICES
#
# Karpenter on AKS is enabled via Azure CLI (az aks update) because the
# azurerm Terraform provider ~> 3.85 does not yet support the
# node_provisioning_profile block (requires azurerm >= 4.57).
#
# This tier:
#   1. Enables Node Autoprovisioning (Karpenter) via Azure CLI
#   2. Applies NodePool and AKSNodeClass CRDs that tell Karpenter
#      how to provision and manage nodes
#
# Unlike Tiers 1-3 (Helm installs), Tier 4 uses az CLI + kubectl apply.
# The Karpenter controller itself is deployed by AKS into kube-system.
#
# TOOLS:
#   1. Karpenter — Node autoscaling via AKS Node Provisioning
#
# PREREQUISITES:
#   - AKS cluster deployed with OIDC issuer enabled
#   - Kubernetes >= 1.29
#   - Azure CLI authenticated (az login)
#
# ============================================================================

# Source common utilities if not already loaded
TIER4_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TIER4_LIB_DIR}/common.sh"

# ----------------------------------------------------------------------------
# CHECK KARPENTER AVAILABILITY
# ----------------------------------------------------------------------------
# Verifies that the Karpenter CRDs exist (indicating Node Autoprovisioning
# was enabled). Without CRDs, kubectl apply will fail.
# ----------------------------------------------------------------------------
karpenter_available() {
    kubectl get crd nodepools.karpenter.sh >/dev/null 2>&1
}

# ----------------------------------------------------------------------------
# ENABLE KARPENTER VIA AZURE CLI
# ----------------------------------------------------------------------------
# Uses 'az aks update' to enable Node Autoprovisioning (Karpenter).
# This is idempotent — re-running when already enabled is a no-op.
#
# When azurerm >= 4.57 is adopted, replace this with:
#   node_provisioning_profile { mode = "Auto" }
# in infrastructure/terraform/aks.tf
# ----------------------------------------------------------------------------
enable_karpenter_nap() {
    progress "Enabling Karpenter Node Autoprovisioning..."

    # Detect cluster name and resource group from current kubeconfig context
    local cluster_name resource_group

    # Try to extract from az aks show using current context
    local context
    context=$(kubectl config current-context 2>/dev/null)
    if [[ -z "$context" ]]; then
        warn "No active kubeconfig context. Cannot determine cluster name."
        return 1
    fi

    # Extract cluster info from Azure CLI
    cluster_name=$(az aks list --query "[?name=='${context}' || fqdn!=null] | [0].name" -o tsv 2>/dev/null)
    resource_group=$(az aks list --query "[?name=='${context}' || fqdn!=null] | [0].resourceGroup" -o tsv 2>/dev/null)

    # Fallback: try to parse from context name (AKS contexts are usually named like the cluster)
    if [[ -z "$cluster_name" ]]; then
        # Common pattern: context name matches cluster name
        cluster_name="${context}"
        resource_group=$(az aks list --query "[?name=='${cluster_name}'].resourceGroup" -o tsv 2>/dev/null)
    fi

    if [[ -z "$cluster_name" || -z "$resource_group" ]]; then
        warn "Could not determine cluster name or resource group from context '${context}'."
        warn "Set AKS_CLUSTER_NAME and AKS_RESOURCE_GROUP environment variables, or enable"
        warn "Karpenter manually: az aks update -g <rg> -n <cluster> --node-provisioning-mode Auto"
        return 1
    fi

    # Allow env var overrides
    cluster_name="${AKS_CLUSTER_NAME:-$cluster_name}"
    resource_group="${AKS_RESOURCE_GROUP:-$resource_group}"

    # Check if already enabled
    if karpenter_available; then
        success "Karpenter already enabled on ${cluster_name}"
        return 0
    fi

    info "Enabling Karpenter on cluster '${cluster_name}' in resource group '${resource_group}'..."
    info "This may take several minutes..."

    if az aks update \
        --resource-group "${resource_group}" \
        --name "${cluster_name}" \
        --node-provisioning-mode Auto \
        --only-show-errors 2>&1; then
        success "Karpenter Node Autoprovisioning enabled"
    else
        warn "Failed to enable Karpenter. You may need to enable it manually:"
        warn "  az aks update -g ${resource_group} -n ${cluster_name} --node-provisioning-mode Auto"
        return 1
    fi

    # Wait for CRDs to appear (AKS deploys Karpenter controller asynchronously)
    info "Waiting for Karpenter CRDs to appear..."
    local retries=0
    local max_retries=30
    while [[ $retries -lt $max_retries ]]; do
        if karpenter_available; then
            success "Karpenter CRDs registered"
            return 0
        fi
        retries=$((retries + 1))
        sleep 10
    done

    warn "Karpenter CRDs not yet available after ${max_retries} attempts."
    warn "The controller may still be starting. Re-run --tier=4 later."
    return 1
}

# ----------------------------------------------------------------------------
# APPLY KARPENTER NODEPOOL CRDs
# ----------------------------------------------------------------------------
install_karpenter_crds() {
    progress "Applying Karpenter NodePool CRDs..."

    if ! karpenter_available; then
        warn "Karpenter CRDs not found. Skipping NodePool application."
        echo ""
        return 0
    fi

    local manifests_dir="${TOOLS_DIR}/karpenter/manifests"

    if [[ ! -d "${manifests_dir}" ]]; then
        warn "Karpenter manifests directory not found: ${manifests_dir}"
        return 0
    fi

    # Apply NodePool and AKSNodeClass manifests
    local applied=0
    for manifest in "${manifests_dir}"/*.yaml; do
        if [[ -f "${manifest}" ]]; then
            info "Applying $(basename "${manifest}")..."
            kubectl apply -f "${manifest}" 2>/dev/null || warn "Could not apply $(basename "${manifest}")"
            applied=$((applied + 1))
        fi
    done

    if [[ $applied -gt 0 ]]; then
        success "Applied ${applied} Karpenter manifest(s)"

        # Verify NodePools exist
        local nodepools
        nodepools=$(kubectl get nodepools --no-headers 2>/dev/null | wc -l || echo "0")
        local nodeclasses
        nodeclasses=$(kubectl get aksnodeclasses --no-headers 2>/dev/null | wc -l || echo "0")
        success "NodePools: ${nodepools}, AKSNodeClasses: ${nodeclasses}"
    fi
    echo ""
}

# ----------------------------------------------------------------------------
# TIER 4 ORCHESTRATOR
# ----------------------------------------------------------------------------
install_tier4() {
    echo -e "${BOLD}── Tier 4: AKS-Managed Services ──${NC}"
    echo ""

    set_total_steps 2

    # Step 1: Enable Karpenter via Azure CLI (if not already enabled)
    enable_karpenter_nap

    # Step 2: Apply NodePool CRDs
    install_karpenter_crds
}

# ----------------------------------------------------------------------------
# TIER 4 SUMMARY
# ----------------------------------------------------------------------------
summary_tier4() {
    echo -e "${BOLD}  Tier 4 — AKS-Managed${NC}"

    if karpenter_available; then
        local nodepools
        nodepools=$(kubectl get nodepools --no-headers 2>/dev/null | wc -l || echo "0")
        if [[ "$nodepools" -gt 0 ]]; then
            echo -e "  ${GREEN}OK    Karpenter: ${nodepools} NodePool(s)${NC}"
            kubectl get nodepools --no-headers 2>/dev/null | while read -r line; do
                local name
                name=$(echo "$line" | awk '{print $1}')
                echo -e "  ${GREEN}      - ${name}${NC}"
            done
        else
            echo -e "  ${YELLOW}SKIP  Karpenter: CRDs present but no NodePools applied${NC}"
        fi
    else
        echo -e "  ${YELLOW}SKIP  Karpenter: not enabled (run install-tools.sh --tier=4)${NC}"
    fi
}

# ----------------------------------------------------------------------------
# TIER 4 CLEANUP
# ----------------------------------------------------------------------------
cleanup_tier4() {
    echo -e "${YELLOW}Removing Tier 4 AKS-managed resources...${NC}"

    if karpenter_available; then
        kubectl delete nodepools --all 2>/dev/null || true
        kubectl delete aksnodeclasses --all 2>/dev/null || true
        success "Karpenter NodePools and AKSNodeClasses removed"
        info "Note: Karpenter controller remains (managed by AKS). To fully disable:"
        info "  az aks update -g <rg> -n <cluster> --node-provisioning-mode Manual"
    else
        info "Karpenter not enabled — nothing to clean up"
    fi
}

# ----------------------------------------------------------------------------
# TIER 4 VALIDATION
# ----------------------------------------------------------------------------
validate_tier4() {
    local issues=0

    echo "Checking Tier 4 — AKS-Managed..."

    if karpenter_available; then
        # Check for Karpenter controller in kube-system
        local karpenter_pods
        karpenter_pods=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$karpenter_pods" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} Karpenter controller: ${karpenter_pods} pod(s) running"
        else
            echo -e "  ${YELLOW}⚠${NC} Karpenter controller: not found in kube-system"
        fi

        # Check NodePools
        local nodepools
        nodepools=$(kubectl get nodepools --no-headers 2>/dev/null | wc -l || echo "0")
        if [[ "$nodepools" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} NodePools: ${nodepools} configured"
            kubectl get nodepools --no-headers 2>/dev/null | while read -r line; do
                local name ready
                name=$(echo "$line" | awk '{print $1}')
                ready=$(echo "$line" | awk '{print $2}')
                echo -e "  ${CYAN}  ${NC} ${name} (ready: ${ready})"
            done
        else
            echo -e "  ${YELLOW}⚠${NC} NodePools: none applied (run install-tools.sh --tier=4)"
        fi

        # Check AKSNodeClasses
        local nodeclasses
        nodeclasses=$(kubectl get aksnodeclasses --no-headers 2>/dev/null | wc -l || echo "0")
        if [[ "$nodeclasses" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} AKSNodeClasses: ${nodeclasses} configured"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Karpenter: not enabled (run install-tools.sh --tier=4 to enable)"
    fi

    return $issues
}
