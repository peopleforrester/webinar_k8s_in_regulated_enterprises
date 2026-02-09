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
#   - --full: Also remove security tool Helm releases
#   - --destroy: Also destroy Terraform infrastructure (AKS cluster)
#
#   The staged approach prevents accidental destruction of expensive
#   infrastructure while making routine cleanup easy.
#
# USAGE:
#   ./cleanup.sh              # Remove demo workloads only (safe)
#   ./cleanup.sh --reset-demo # Reset for fresh demo (clean + redeploy vulnerable app)
#   ./cleanup.sh --full       # Also remove Helm releases
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
#   --full (adds):
#     - Kubescape Helm release and namespace
#     - Trivy Operator Helm release and namespace
#     - Kyverno Helm release and namespace
#     - Falcosidekick Helm release
#     - Falco Helm release and namespace
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
#   Keep the cluster running (skip --destroy) when:
#   - You'll demo again soon
#   - Development/testing in progress
#   - Re-creation time (10 min) is unacceptable
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."

# Terminal colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Cleanup${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# ============================================================================
# ARGUMENT PARSING
# ============================================================================
# We use a simple while loop to parse arguments. This is more readable
# than getopts for simple flags and provides good error messages.
#
# FLAGS:
#   --reset-demo : Clean workloads/policies, then redeploy vulnerable app for fresh demo
#   --full       : Also remove Helm-installed security tools
#   --destroy    : Also destroy Terraform-managed Azure infrastructure
#   --help       : Show usage and exit
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
            echo "  --full        Remove security tools (Helm releases)"
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
# Demo workloads are the vulnerable and compliant application deployments.
# These are safe to remove as they're just for demonstration purposes.
#
# ORDER OF DELETION:
#   1. Delete resources within namespace first
#   2. Then delete the namespace itself
#
# This order is actually not required (namespace deletion will cascade),
# but it provides clearer output and faster cleanup since kubectl doesn't
# have to wait for namespace finalizers.
#
# --ignore-not-found prevents errors if resources don't exist, which is
# common when re-running cleanup or cleaning up partial deployments.
# ============================================================================
echo -e "${YELLOW}[1/4] Removing demo workloads...${NC}"

# Remove vulnerable app resources
kubectl delete -f "${ROOT_DIR}/demo-workloads/vulnerable-app/" --ignore-not-found 2>/dev/null || true

# Remove compliant app resources
kubectl delete -f "${ROOT_DIR}/demo-workloads/compliant-app/" --ignore-not-found 2>/dev/null || true

# Delete namespaces (this will also delete any remaining resources)
kubectl delete namespace vulnerable-app --ignore-not-found 2>/dev/null || true
kubectl delete namespace compliant-app --ignore-not-found 2>/dev/null || true

echo -e "${GREEN}  Demo workloads removed${NC}"
echo ""

# ============================================================================
# STEP 2: REMOVE KYVERNO POLICIES
# ============================================================================
# Kyverno policies are ClusterPolicies, so they persist across namespaces.
# We need to explicitly remove them to reset the cluster to an
# "unprotected" state for the next demo run.
#
# The -k flag uses kustomization.yaml to identify all policy resources.
# This ensures we remove exactly what was deployed.
# ============================================================================
echo -e "${YELLOW}[2/4] Removing Kyverno policies...${NC}"
kubectl delete -k "${ROOT_DIR}/security-tools/kyverno/policies/" --ignore-not-found 2>/dev/null || true
echo -e "${GREEN}  Kyverno policies removed${NC}"
echo ""

# ============================================================================
# STEP 3: REMOVE RBAC RESOURCES
# ============================================================================
# The vulnerable app creates cluster-wide RBAC resources that allow
# cross-namespace secret access. These must be explicitly cleaned up
# as they don't belong to any namespace.
#
# SECURITY NOTE: Leftover RBAC resources are a common source of
# privilege escalation. Always clean up ClusterRoles and
# ClusterRoleBindings when removing applications.
# ============================================================================
echo -e "${YELLOW}[3/4] Removing RBAC resources...${NC}"
kubectl delete clusterrole vulnerable-app-role --ignore-not-found 2>/dev/null || true
kubectl delete clusterrolebinding vulnerable-app-binding --ignore-not-found 2>/dev/null || true
echo -e "${GREEN}  RBAC resources removed${NC}"
echo ""

# ============================================================================
# STEP 4: OPTIONAL - REMOVE SECURITY TOOLS
# ============================================================================
# When --full is specified, we uninstall all Helm releases for the
# security tools. This is useful when:
#   - Testing fresh installations
#   - Changing tool configurations significantly
#   - Freeing up cluster resources
#
# UNINSTALL ORDER:
#   We remove in reverse order of dependency:
#   1. Kubescape (no dependencies)
#   2. Trivy Operator (no dependencies)
#   3. Kyverno (no dependencies)
#   4. Falcosidekick (depends on Falco output)
#   5. Falco (base tool)
#
# Each uninstall removes the Helm release but leaves CRDs by default.
# Namespace deletion ensures CRDs are also removed.
# ============================================================================
if [[ "${FULL_CLEANUP}" == "true" ]]; then
    echo -e "${YELLOW}[4/4] Removing security tools (Helm releases)...${NC}"

    # Uninstall Helm releases
    # The '2>/dev/null || true' pattern suppresses "release not found" errors
    helm uninstall kubescape -n kubescape 2>/dev/null || true
    helm uninstall trivy-operator -n trivy-system 2>/dev/null || true
    helm uninstall kyverno -n kyverno 2>/dev/null || true
    helm uninstall falcosidekick -n falco 2>/dev/null || true
    helm uninstall falco -n falco 2>/dev/null || true

    # Delete namespaces to clean up any remaining resources and CRDs
    kubectl delete namespace kubescape --ignore-not-found 2>/dev/null || true
    kubectl delete namespace trivy-system --ignore-not-found 2>/dev/null || true
    kubectl delete namespace kyverno --ignore-not-found 2>/dev/null || true
    kubectl delete namespace falco --ignore-not-found 2>/dev/null || true

    echo -e "${GREEN}  Security tools removed${NC}"
else
    echo -e "${YELLOW}[4/4] Skipping security tools removal (use --full to remove)${NC}"
fi
echo ""

# ============================================================================
# OPTIONAL: DESTROY INFRASTRUCTURE
# ============================================================================
# When --destroy is specified, we run terraform destroy to remove all
# Azure resources. This is a DESTRUCTIVE operation that:
#   - Deletes the AKS cluster and all workloads
#   - Deletes the Log Analytics Workspace and all logs
#   - Deletes the Resource Group
#   - CANNOT BE UNDONE
#
# SAFETY: We require the user to type "destroy" to confirm.
# This double-confirmation pattern prevents accidental infrastructure
# deletion from a mistyped command.
#
# -auto-approve skips Terraform's confirmation because we've already
# confirmed with the user. This makes the script non-interactive after
# the initial confirmation.
#
# COST: After destruction, you won't be charged. However, you'll need
# to wait 10+ minutes to recreate the cluster.
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
# When --reset-demo is specified, we redeploy the vulnerable app after
# cleanup so the cluster is ready for a fresh demo run. This is the
# pre-webinar reset command:
#   1. Workloads and policies are removed (steps 1-3 above)
#   2. Vulnerable app is redeployed (so the attack phase works)
#   3. Security tools remain installed (Falco, Kyverno engine, etc.)
#   4. Kyverno policies are NOT applied (so vulnerable app can deploy)
#
# After running --reset-demo, the demo script starts clean:
#   - Vulnerable app is running (for attack + detect phases)
#   - No policies are active (apply them live in prevent phase)
#   - Falco is watching (detects attack simulation immediately)
# ============================================================================
if [[ "${RESET_DEMO}" == "true" ]]; then
    echo -e "${YELLOW}[5/5] Resetting for fresh demo...${NC}"
    echo -e "  Deploying vulnerable app..."
    kubectl apply -f "${ROOT_DIR}/demo-workloads/vulnerable-app/namespace.yaml" 2>/dev/null || true
    kubectl apply -f "${ROOT_DIR}/demo-workloads/vulnerable-app/" 2>/dev/null || true

    # Wait for pods to be ready
    echo -e "  Waiting for vulnerable app pods..."
    kubectl wait --for=condition=available deployment/vulnerable-app \
        -n vulnerable-app --timeout=120s 2>/dev/null || true

    echo -e "${GREEN}  Demo reset complete - vulnerable app running, no policies active${NC}"
    echo ""
    echo -e "${BOLD}  Demo is ready! Follow docs/DEMO-SCRIPT.md${NC}"
fi

echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}  Cleanup complete${NC}"
echo -e "${BOLD}========================================${NC}"
