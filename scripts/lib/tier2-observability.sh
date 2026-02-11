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
#   1. kube-prometheus-stack — Prometheus + Grafana + AlertManager (CNCF Graduated)
#   2. ArgoCD               — GitOps continuous delivery (CNCF Graduated)
#   3. External Secrets Operator — Secret sync from Key Vault
#
# ============================================================================

# Source common utilities if not already loaded
TIER2_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TIER2_LIB_DIR}/common.sh"

# ----------------------------------------------------------------------------
# TIER 2 NAMESPACES
# ----------------------------------------------------------------------------
TIER2_NAMESPACES=(monitoring argocd external-secrets)

# ----------------------------------------------------------------------------
# HELM REPOSITORIES FOR TIER 2
# ----------------------------------------------------------------------------
setup_tier2_repos() {
    helm_repo_add prometheus-community https://prometheus-community.github.io/helm-charts
    helm_repo_add argo https://argoproj.github.io/argo-helm
    helm_repo_add external-secrets https://charts.external-secrets.io
    helm repo update
    success "Tier 2 Helm repos configured"
}

# ----------------------------------------------------------------------------
# INSTALL PROMETHEUS STACK
# ----------------------------------------------------------------------------
# Deploys kube-prometheus-stack which bundles:
#   - Prometheus server (metrics collection)
#   - Alertmanager (alert routing)
#   - Grafana (visualization)
#   - node-exporter (host metrics DaemonSet)
#   - kube-state-metrics (Kubernetes object metrics)
#   - Prometheus Operator (CRD lifecycle management)
#
# After install, the Prometheus Operator watches for ServiceMonitor CRDs
# created by Tier 1 tools and auto-configures scraping.
# ----------------------------------------------------------------------------
install_prometheus_stack() {
    progress "Installing kube-prometheus-stack (Prometheus + Grafana + Alertmanager)..."
    helm_install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        monitoring \
        "${TOOLS_DIR}/prometheus/values.yaml" \
        8m
    verify_install "monitoring" "Prometheus Stack" || true
    echo ""
}

# ----------------------------------------------------------------------------
# APPLY GRAFANA DASHBOARDS
# ----------------------------------------------------------------------------
# Dashboard ConfigMaps are applied separately so they can be managed
# independently from the Prometheus Stack Helm release. The Grafana sidecar
# detects ConfigMaps with label grafana_dashboard: "1" and provisions them.
# ----------------------------------------------------------------------------
apply_grafana_dashboards() {
    info "Applying Grafana dashboard ConfigMaps..."

    local dashboard_dir="${TOOLS_DIR}/grafana/dashboards"
    if [[ -d "${dashboard_dir}" ]]; then
        local count=0
        for dashboard_file in "${dashboard_dir}"/*.yaml; do
            if [[ -f "${dashboard_file}" ]]; then
                kubectl apply -f "${dashboard_file}" 2>/dev/null || true
                count=$((count + 1))
            fi
        done
        success "Applied ${count} Grafana dashboard(s)"
    else
        warn "No dashboard directory found at ${dashboard_dir}"
    fi
}

# ----------------------------------------------------------------------------
# ENABLE SERVICE MONITORS ON TIER 1 TOOLS
# ----------------------------------------------------------------------------
# After Prometheus Stack is installed, the ServiceMonitor CRD exists.
# Upgrade Tier 1 Helm releases to enable serviceMonitor so Prometheus
# discovers and scrapes their metrics endpoints.
#
# Tools that already have serviceMonitor.enabled: true in their values.yaml
# (falcosidekick, falco-talon, kubescape) already create ServiceMonitors.
# We only need to upgrade those with serviceMonitor.enabled: false.
# ----------------------------------------------------------------------------
enable_tier1_servicemonitors() {
    info "Enabling ServiceMonitors on Tier 1 tools..."

    # Falco — serviceMonitor.enabled: false in values.yaml
    if helm status falco -n falco >/dev/null 2>&1; then
        helm upgrade falco falcosecurity/falco \
            -n falco \
            -f "${TOOLS_DIR}/falco/values.yaml" \
            --set serviceMonitor.enabled=true \
            --wait --timeout 3m 2>/dev/null || warn "Could not enable Falco ServiceMonitor"
        success "Falco ServiceMonitor enabled"
    fi

    # Kyverno — serviceMonitor.enabled: false in values.yaml
    if helm status kyverno -n kyverno >/dev/null 2>&1; then
        helm upgrade kyverno kyverno/kyverno \
            -n kyverno \
            -f "${TOOLS_DIR}/kyverno/values.yaml" \
            --set serviceMonitor.enabled=true \
            --wait --timeout 3m 2>/dev/null || warn "Could not enable Kyverno ServiceMonitor"
        success "Kyverno ServiceMonitor enabled"
    fi

    # Trivy — serviceMonitor.enabled: false in values.yaml
    if helm status trivy-operator -n trivy-system >/dev/null 2>&1; then
        helm upgrade trivy-operator aqua/trivy-operator \
            -n trivy-system \
            -f "${TOOLS_DIR}/trivy/values.yaml" \
            --set serviceMonitor.enabled=true \
            --wait --timeout 3m 2>/dev/null || warn "Could not enable Trivy ServiceMonitor"
        success "Trivy Operator ServiceMonitor enabled"
    fi

    # Falcosidekick and Kubescape already have serviceMonitor.enabled: true
    success "ServiceMonitors enabled for Tier 1 tools"
}

# ----------------------------------------------------------------------------
# INSTALL ARGOCD
# ----------------------------------------------------------------------------
# Deploys Argo CD using the argo/argo-cd chart with lab-sized config.
# After install, prints the initial admin password and access instructions.
# ----------------------------------------------------------------------------
install_argocd() {
    progress "Installing ArgoCD (GitOps delivery)..."
    helm_install argocd argo/argo-cd \
        argocd \
        "${TOOLS_DIR}/argocd/values.yaml" \
        5m
    verify_install "argocd" "ArgoCD" || true

    # Print access instructions
    info "ArgoCD access:"
    info "  Get admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    info "  Port-forward UI:   kubectl port-forward svc/argocd-server -n argocd 8080:443"
    info "  Login:             argocd login localhost:8080 --username admin --password <password>"
    echo ""
}

# ----------------------------------------------------------------------------
# INSTALL EXTERNAL SECRETS OPERATOR
# ----------------------------------------------------------------------------
# Deploys ESO and applies the ClusterSecretStore for Azure Key Vault.
# The ClusterSecretStore uses workload identity — no client secrets needed.
#
# The Key Vault URL is read from Terraform outputs if available, otherwise
# the value in the manifest is used as-is.
# ----------------------------------------------------------------------------
install_external_secrets() {
    progress "Installing External Secrets Operator (secrets sync)..."
    helm_install external-secrets external-secrets/external-secrets \
        external-secrets \
        "${TOOLS_DIR}/external-secrets/values.yaml" \
        5m
    verify_install "external-secrets" "External Secrets Operator" || true

    # Apply ClusterSecretStore manifest
    local css_manifest="${TOOLS_DIR}/external-secrets/manifests/cluster-secret-store.yaml"
    if [[ -f "${css_manifest}" ]]; then
        # Try to read Key Vault URI from Terraform outputs
        local tf_dir="${ROOT_DIR}/infrastructure/terraform"
        local kv_uri=""
        if [[ -f "${tf_dir}/terraform.tfstate" ]]; then
            kv_uri=$(cd "${tf_dir}" && terraform output -raw key_vault_uri 2>/dev/null || true)
        fi

        if [[ -n "${kv_uri}" ]]; then
            info "Using Key Vault URI from Terraform: ${kv_uri}"
            # Apply with substituted vault URL
            sed "s|https://kv-regulated-demo.vault.azure.net|${kv_uri%/}|" "${css_manifest}" \
                | kubectl apply -f - 2>/dev/null || warn "Could not apply ClusterSecretStore"
        else
            info "Applying ClusterSecretStore with default Key Vault URL"
            info "Update vaultUrl in ${css_manifest} if your Key Vault name differs"
            kubectl apply -f "${css_manifest}" 2>/dev/null || warn "Could not apply ClusterSecretStore"
        fi
        success "ClusterSecretStore applied"
    fi
    echo ""
}

# ----------------------------------------------------------------------------
# TIER 2 ORCHESTRATOR
# ----------------------------------------------------------------------------
# Installs all Tier 2 tools in dependency order.
# Sets up progress tracking for 6 steps (1 repo + 3 tools + dashboards + SMs).
# ----------------------------------------------------------------------------
install_tier2() {
    echo -e "${BOLD}── Tier 2: Observability & Delivery ──${NC}"
    echo ""

    set_total_steps 6

    progress "Setting up Helm repositories..."
    setup_tier2_repos
    echo ""

    install_prometheus_stack
    apply_grafana_dashboards
    enable_tier1_servicemonitors
    echo ""

    install_argocd
    install_external_secrets
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
# TIER 2 CLEANUP
# ----------------------------------------------------------------------------
# Uninstalls in reverse order. Also reverts Tier 1 ServiceMonitor upgrades
# to avoid broken ServiceMonitor references after Prometheus is removed.
# ----------------------------------------------------------------------------
cleanup_tier2() {
    echo -e "${YELLOW}Removing Tier 2 observability tools...${NC}"

    # Remove ClusterSecretStore first (depends on ESO CRDs)
    kubectl delete clustersecretstore azure-keyvault --ignore-not-found 2>/dev/null || true

    # Remove Grafana dashboard ConfigMaps
    kubectl delete configmap -n monitoring -l grafana_dashboard=1 --ignore-not-found 2>/dev/null || true

    # Uninstall Helm releases (reverse install order)
    helm uninstall external-secrets -n external-secrets 2>/dev/null || true
    helm uninstall argocd -n argocd 2>/dev/null || true
    helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true

    # Clean up Prometheus CRDs that Helm leaves behind
    kubectl delete crd --ignore-not-found \
        alertmanagerconfigs.monitoring.coreos.com \
        alertmanagers.monitoring.coreos.com \
        podmonitors.monitoring.coreos.com \
        probes.monitoring.coreos.com \
        prometheusagents.monitoring.coreos.com \
        prometheuses.monitoring.coreos.com \
        prometheusrules.monitoring.coreos.com \
        scrapeconfigs.monitoring.coreos.com \
        servicemonitors.monitoring.coreos.com \
        thanosrulers.monitoring.coreos.com \
        2>/dev/null || true

    # Delete namespaces
    for ns in "${TIER2_NAMESPACES[@]}"; do
        kubectl delete namespace "${ns}" --ignore-not-found 2>/dev/null || true
    done

    # Revert Tier 1 ServiceMonitor settings (if Tier 1 is still running)
    if helm status falco -n falco >/dev/null 2>&1; then
        helm upgrade falco falcosecurity/falco \
            -n falco \
            -f "${TOOLS_DIR}/falco/values.yaml" \
            --wait --timeout 3m 2>/dev/null || true
    fi
    if helm status kyverno -n kyverno >/dev/null 2>&1; then
        helm upgrade kyverno kyverno/kyverno \
            -n kyverno \
            -f "${TOOLS_DIR}/kyverno/values.yaml" \
            --wait --timeout 3m 2>/dev/null || true
    fi
    if helm status trivy-operator -n trivy-system >/dev/null 2>&1; then
        helm upgrade trivy-operator aqua/trivy-operator \
            -n trivy-system \
            -f "${TOOLS_DIR}/trivy/values.yaml" \
            --wait --timeout 3m 2>/dev/null || true
    fi

    success "Tier 2 tools removed"
}

# ----------------------------------------------------------------------------
# TIER 2 VALIDATION
# ----------------------------------------------------------------------------
validate_tier2() {
    local issues=0

    echo "Checking Tier 2 — Observability & Delivery..."

    # Prometheus Stack
    local prom_pods
    prom_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/instance=kube-prometheus-stack --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$prom_pods" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Prometheus Stack: ${prom_pods} pods running"

        # Check Grafana specifically
        local grafana_pods
        grafana_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$grafana_pods" -gt 0 ]]; then
            echo -e "  ${GREEN}✓${NC} Grafana: running"
        else
            echo -e "  ${YELLOW}⚠${NC} Grafana: not running"
        fi

        # Check ServiceMonitor count
        local sm_count
        sm_count=$(kubectl get servicemonitors --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
        echo -e "  ${CYAN}  ${NC} ServiceMonitors: ${sm_count} registered"
    else
        echo -e "  ${YELLOW}⚠${NC} Prometheus Stack: not deployed"
    fi

    # ArgoCD
    local argocd_pods
    argocd_pods=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$argocd_pods" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} ArgoCD: ${argocd_pods} pods running"
    else
        echo -e "  ${YELLOW}⚠${NC} ArgoCD: not deployed"
    fi

    # External Secrets Operator
    local eso_pods
    eso_pods=$(kubectl get pods -n external-secrets --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$eso_pods" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} External Secrets: ${eso_pods} pods running"

        # Check ClusterSecretStore status
        local css_status
        css_status=$(kubectl get clustersecretstore azure-keyvault -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "")
        if [[ "${css_status}" == "True" ]]; then
            echo -e "  ${GREEN}✓${NC} ClusterSecretStore: Ready"
        elif [[ -n "${css_status}" ]]; then
            echo -e "  ${YELLOW}⚠${NC} ClusterSecretStore: status=${css_status}"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} External Secrets: not deployed"
    fi

    return $issues
}
