#!/usr/bin/env bash
# Setup AKS cluster using Terraform
# Deploys all infrastructure and configures kubectl access

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../infrastructure/terraform"
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  AKS Regulated Enterprise - Cluster Setup${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}[1/6] Checking prerequisites...${NC}"
MISSING=()
command -v az >/dev/null 2>&1 || MISSING+=("az (Azure CLI)")
command -v terraform >/dev/null 2>&1 || MISSING+=("terraform")
command -v kubectl >/dev/null 2>&1 || MISSING+=("kubectl")
command -v helm >/dev/null 2>&1 || MISSING+=("helm")

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${RED}Missing required tools:${NC}"
    for tool in "${MISSING[@]}"; do
        echo "  - ${tool}"
    done
    exit 1
fi
echo -e "${GREEN}  All prerequisites found${NC}"
echo ""

# Check Azure login
echo -e "${YELLOW}[2/6] Checking Azure authentication...${NC}"
if ! az account show >/dev/null 2>&1; then
    echo -e "${RED}Not logged in to Azure. Run: az login${NC}"
    exit 1
fi
ACCOUNT=$(az account show --query name -o tsv)
echo -e "${GREEN}  Logged in to: ${ACCOUNT}${NC}"
echo ""

# Check terraform.tfvars exists
echo -e "${YELLOW}[3/6] Checking Terraform configuration...${NC}"
if [[ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
    echo -e "${YELLOW}  terraform.tfvars not found. Copying from example...${NC}"
    cp "${TERRAFORM_DIR}/terraform.tfvars.example" "${TERRAFORM_DIR}/terraform.tfvars"
    echo -e "${RED}  Please edit ${TERRAFORM_DIR}/terraform.tfvars with your values${NC}"
    echo "  Then re-run this script."
    exit 1
fi
echo -e "${GREEN}  terraform.tfvars found${NC}"
echo ""

# Terraform init
echo -e "${YELLOW}[4/6] Initializing Terraform... (this may take a minute)${NC}"
cd "${TERRAFORM_DIR}"
terraform init -upgrade 2>&1 | tail -1
echo -e "${GREEN}  Terraform initialized${NC}"
echo ""

# Terraform plan
echo -e "${YELLOW}[5/6] Planning infrastructure changes...${NC}"
terraform plan -out=tfplan 2>&1 | tail -5
echo ""
echo -e "${YELLOW}  Review the plan above. Proceed with apply?${NC}"
read -r -p "  Type 'yes' to continue: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

# Terraform apply
echo -e "${YELLOW}[6/6] Applying infrastructure... (this takes 5-10 minutes)${NC}"
terraform apply tfplan 2>&1 | tail -10
rm -f tfplan
echo ""

# Get AKS credentials
echo -e "${YELLOW}Configuring kubectl...${NC}"
RG=$(terraform output -raw resource_group_name)
CLUSTER=$(terraform output -raw aks_cluster_name)
az aks get-credentials --resource-group "${RG}" --name "${CLUSTER}" --overwrite-existing
echo ""

# Verify connection
echo -e "${YELLOW}Verifying cluster connection...${NC}"
kubectl get nodes
echo ""

echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}  Cluster setup complete!${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "Next step: Install security tools"
echo "  ./install-security-tools.sh"
