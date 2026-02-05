#!/usr/bin/env bash
# Cleanup script - removes demo workloads and optionally security tools
# Does NOT destroy infrastructure by default

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Cleanup${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# Parse arguments
FULL_CLEANUP=false
DESTROY_INFRA=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --full) FULL_CLEANUP=true; shift ;;
        --destroy) DESTROY_INFRA=true; shift ;;
        -h|--help)
            echo "Usage: cleanup.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --full      Remove security tools (Helm releases)"
            echo "  --destroy   Destroy Terraform infrastructure (AKS cluster)"
            echo "  -h, --help  Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Step 1: Remove demo workloads
echo -e "${YELLOW}[1/4] Removing demo workloads...${NC}"
kubectl delete -f "${ROOT_DIR}/demo-workloads/vulnerable-app/" --ignore-not-found 2>/dev/null || true
kubectl delete -f "${ROOT_DIR}/demo-workloads/compliant-app/" --ignore-not-found 2>/dev/null || true
kubectl delete namespace vulnerable-app --ignore-not-found 2>/dev/null || true
kubectl delete namespace compliant-app --ignore-not-found 2>/dev/null || true
echo -e "${GREEN}  Demo workloads removed${NC}"
echo ""

# Step 2: Remove Kyverno policies
echo -e "${YELLOW}[2/4] Removing Kyverno policies...${NC}"
kubectl delete -k "${ROOT_DIR}/security-tools/kyverno/policies/" --ignore-not-found 2>/dev/null || true
echo -e "${GREEN}  Kyverno policies removed${NC}"
echo ""

# Step 3: Remove RBAC resources
echo -e "${YELLOW}[3/4] Removing RBAC resources...${NC}"
kubectl delete clusterrole vulnerable-app-role --ignore-not-found 2>/dev/null || true
kubectl delete clusterrolebinding vulnerable-app-binding --ignore-not-found 2>/dev/null || true
echo -e "${GREEN}  RBAC resources removed${NC}"
echo ""

# Step 4: Optionally remove security tools
if [[ "${FULL_CLEANUP}" == "true" ]]; then
    echo -e "${YELLOW}[4/4] Removing security tools (Helm releases)...${NC}"
    helm uninstall kubescape -n kubescape 2>/dev/null || true
    helm uninstall trivy-operator -n trivy-system 2>/dev/null || true
    helm uninstall kyverno -n kyverno 2>/dev/null || true
    helm uninstall falcosidekick -n falco 2>/dev/null || true
    helm uninstall falco -n falco 2>/dev/null || true

    kubectl delete namespace kubescape --ignore-not-found 2>/dev/null || true
    kubectl delete namespace trivy-system --ignore-not-found 2>/dev/null || true
    kubectl delete namespace kyverno --ignore-not-found 2>/dev/null || true
    kubectl delete namespace falco --ignore-not-found 2>/dev/null || true
    echo -e "${GREEN}  Security tools removed${NC}"
else
    echo -e "${YELLOW}[4/4] Skipping security tools removal (use --full to remove)${NC}"
fi
echo ""

# Optionally destroy infrastructure
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

echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}  Cleanup complete${NC}"
echo -e "${BOLD}========================================${NC}"
