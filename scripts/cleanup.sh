#!/usr/bin/env bash
# ============================================================================
# ABOUTME: Cleanup script for removing demo resources and optionally infrastructure.
# ABOUTME: Provides safe, staged cleanup with explicit confirmation for destructive operations.
# ============================================================================
#
# PURPOSE:
#   This script provides safe cleanup of demo resources with multiple levels:
#   - Default: Remove demo workloads and policies only
#   - --reset-demo: Remove workloads/policies, then redeploy vulnerable app (pre-demo reset)
#   - --full: Also remove security tool Helm releases (all tiers)
#   - --destroy: Also destroy Terraform infrastructure (AKS cluster)
#
#   The staged approach prevents accidental destruction of expensive
#   infrastructure while making routine cleanup easy.
#
# USAGE:
#   ./cleanup.sh              # Remove demo workloads only (safe)
#   ./cleanup.sh --reset-demo # Reset for fresh demo (clean + redeploy vulnerable app)
#   ./cleanup.sh --full       # Also remove Helm releases (all tiers)
#   ./cleanup.sh --destroy    # Also destroy Azure infrastructure
#   ./cleanup.sh --full --destroy  # Complete teardown
#   ./cleanup.sh --help       # Show usage
#
# WHAT GETS REMOVED (by stage):
#
#   DEFAULT (no flags):
#     - vulnerable-app namespace and all resources
#     - compliant-app namespace and all resources
#     - Kyverno policies (ClusterPolicies)
#     - RBAC resources (ClusterRole, ClusterRoleBinding)
#
#   --reset-demo (default cleanup + redeploy):
#     - Everything in DEFAULT
#     - Then redeploys vulnerable-app (namespace + workload)
#     - Leaves security tools running, policies removed
#     - Cluster is ready for a fresh demo run
#
#   --full (adds — reverse tier order):
#     - Tier 4: Karpenter NodePools
#     - Tier 3: Harbor, Crossplane, Istio
#     - Tier 2: External Secrets, ArgoCD, Prometheus
#     - Tier 1: Kubescape, Trivy, Kyverno, Falcosidekick, Falco
#
#   --destroy (adds):
#     - Azure Resource Group (contains all Azure resources)
#     - AKS cluster
#     - Log Analytics Workspace
#     - Container Registry (if configured)
#
# SAFETY FEATURES:
#   - Default behavior is non-destructive (just removes demo workloads)
#   - --destroy requires typing "destroy" to confirm
#   - Uses --ignore-not-found to handle partial states gracefully
#   - Error handling with 'set -euo pipefail' prevents cascading failures
#
# COST IMPLICATIONS:
#   AKS clusters incur hourly charges. Use --destroy when:
#   - Demo is complete
#   - Not needed for several days
#   - Cost optimization is a priority
#
# ============================================================================

set -euo pipefail

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tier1-security.sh"
source "${SCRIPT_DIR}/lib/tier2-observability.sh"
source "${SCRIPT_DIR}/lib/tier3-platform.sh"
source "${SCRIPT_DIR}/lib/tier4-aks-managed.sh"

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Cleanup${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# ============================================================================
# ARGUMENT PARSING
# ============================================================================
FULL_CLEANUP=false
DESTROY_INFRA=false
RESET_DEMO=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --reset-demo)
            RESET_DEMO=true
            shift
            ;;
        --full)
            FULL_CLEANUP=true
            shift
            ;;
        --destroy)
            DESTROY_INFRA=true
            shift
            ;;
        -h|--help)
            echo "Usage: cleanup.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --reset-demo  Reset for fresh demo (clean + redeploy vulnerable app)"
            echo "  --full        Remove all tool Helm releases (Tiers 1-4)"
            echo "  --destroy     Destroy Terraform infrastructure (AKS cluster)"
            echo "  -h, --help    Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# STEP 1: REMOVE DEMO WORKLOADS
# ============================================================================
echo -e "${YELLOW}[1/4] Removing demo workloads...${NC}"

kubectl delete -f "${ROOT_DIR}/workloads/vulnerable-app/" --ignore-not-found 2>/dev/null || true
kubectl delete -f "${ROOT_DIR}/workloads/compliant-app/" --ignore-not-found 2>/dev/null || true

kubectl delete namespace vulnerable-app --ignore-not-found 2>/dev/null || true
kubectl delete namespace compliant-app --ignore-not-found 2>/dev/null || true

echo -e "${GREEN}  Demo workloads removed${NC}"
echo ""

# ============================================================================
# STEP 2: REMOVE KYVERNO POLICIES
# ============================================================================
echo -e "${YELLOW}[2/4] Removing Kyverno policies...${NC}"
kubectl delete -k "${ROOT_DIR}/tools/kyverno/policies/" --ignore-not-found 2>/dev/null || true
echo -e "${GREEN}  Kyverno policies removed${NC}"
echo ""

# ============================================================================
# STEP 3: REMOVE RBAC RESOURCES
# ============================================================================
echo -e "${YELLOW}[3/4] Removing RBAC resources...${NC}"
kubectl delete clusterrole vulnerable-app-role --ignore-not-found 2>/dev/null || true
kubectl delete clusterrolebinding vulnerable-app-binding --ignore-not-found 2>/dev/null || true
echo -e "${GREEN}  RBAC resources removed${NC}"
echo ""

# ============================================================================
# STEP 4: OPTIONAL - REMOVE ALL TOOL TIERS
# ============================================================================
# When --full is specified, uninstall all Helm releases in reverse tier order.
# Reverse order respects dependencies (higher tiers depend on lower ones).
# ============================================================================
if [[ "${FULL_CLEANUP}" == "true" ]]; then
    echo -e "${YELLOW}[4/4] Removing all tool tiers (reverse order)...${NC}"
    echo ""

    cleanup_tier4
    echo ""
    cleanup_tier3
    echo ""
    cleanup_tier2
    echo ""
    cleanup_tier1
else
    echo -e "${YELLOW}[4/4] Skipping tool removal (use --full to remove all tiers)${NC}"
fi
echo ""

# ============================================================================
# OPTIONAL: DESTROY INFRASTRUCTURE
# ============================================================================
if [[ "${DESTROY_INFRA}" == "true" ]]; then
    echo -e "${RED}WARNING: This will destroy the AKS cluster and all Azure resources!${NC}"
    read -r -p "Type 'destroy' to confirm: " CONFIRM
    if [[ "${CONFIRM}" == "destroy" ]]; then
        echo -e "${YELLOW}Destroying infrastructure...${NC}"
        cd "${ROOT_DIR}/infrastructure/terraform"
        terraform destroy -auto-approve
        echo -e "${GREEN}  Infrastructure destroyed${NC}"
    else
        echo "Aborted infrastructure destruction."
    fi
fi

# ============================================================================
# OPTIONAL: RESET FOR FRESH DEMO
# ============================================================================
if [[ "${RESET_DEMO}" == "true" ]]; then
    echo -e "${YELLOW}[5/5] Resetting for fresh demo...${NC}"
    echo -e "  Deploying vulnerable app..."
    kubectl apply -f "${ROOT_DIR}/workloads/vulnerable-app/namespace.yaml" 2>/dev/null || true
    kubectl apply -f "${ROOT_DIR}/workloads/vulnerable-app/" 2>/dev/null || true

    echo -e "  Waiting for vulnerable app pods..."
    kubectl wait --for=condition=available deployment/vulnerable-app \
        -n vulnerable-app --timeout=120s 2>/dev/null || true

    echo -e "${GREEN}  Demo reset complete - vulnerable app running, no policies active${NC}"
    echo ""
    echo -e "${BOLD}  Demo is ready! Follow scenarios/attack-detect-prevent/DEMO-SCRIPT.md${NC}"
fi

echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}  Cleanup complete${NC}"
echo -e "${BOLD}========================================${NC}"
