#!/usr/bin/env bash
# ============================================================================
# ABOUTME: Automated AKS cluster setup script for regulated enterprise demos.
# ABOUTME: Deploys Azure infrastructure via Terraform and configures kubectl.
# ============================================================================
#
# PURPOSE:
#   This script automates the complete setup of an Azure Kubernetes Service (AKS)
#   cluster configured for regulated enterprise environments. It handles:
#   - Prerequisite validation (tools and authentication)
#   - Terraform initialization and infrastructure deployment
#   - kubectl configuration for cluster access
#
# PREREQUISITES:
#   1. Azure CLI (az) - Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
#   2. Terraform >= 1.0 - Install: https://learn.hashicorp.com/tutorials/terraform/install-cli
#   3. kubectl - Install: https://kubernetes.io/docs/tasks/tools/
#   4. Helm >= 3.0 - Install: https://helm.sh/docs/intro/install/
#   5. Active Azure subscription with Owner or Contributor role
#   6. Azure CLI authenticated (run: az login)
#
# USAGE:
#   ./setup-cluster.sh
#
#   The script is interactive and will:
#   - Check for all required tools
#   - Verify Azure authentication
#   - Create terraform.tfvars from template if needed
#   - Show a plan and ask for confirmation before applying
#
# WHAT GETS CREATED:
#   - Azure Resource Group
#   - AKS cluster with:
#     * Azure CNI networking (required for network policies)
#     * Azure Policy add-on (for compliance)
#     * Microsoft Defender for Cloud integration
#     * Private cluster option (configurable)
#   - Log Analytics Workspace for monitoring
#   - Azure Container Registry (if configured)
#
# ESTIMATED TIME: 10-15 minutes for cluster creation
#
# COST WARNING:
#   AKS clusters incur Azure charges. Estimated cost: $100-300/month depending
#   on node count and size. Remember to run cleanup.sh --destroy when done.
#
# SECURITY CONSIDERATIONS:
#   - This script stores Terraform state locally by default
#   - For production, configure remote state in Azure Storage
#   - Review terraform.tfvars before applying
#
# ============================================================================

# ----------------------------------------------------------------------------
# BASH STRICT MODE
# ----------------------------------------------------------------------------
# These options make the script fail fast and prevent subtle bugs:
#   -e : Exit immediately if any command fails (non-zero exit code)
#   -u : Treat unset variables as errors (prevents typos)
#   -o pipefail : Pipeline fails if any command in it fails (not just the last)
#
# Why this matters for infrastructure scripts:
#   Without strict mode, a failed 'terraform plan' might not stop the script,
#   leading to 'terraform apply' running with stale or no plan. This could
#   result in unexpected infrastructure changes.
# ----------------------------------------------------------------------------
set -euo pipefail

# ----------------------------------------------------------------------------
# SCRIPT DIRECTORY RESOLUTION
# ----------------------------------------------------------------------------
# This technique reliably finds the script's directory regardless of how it's
# invoked (relative path, absolute path, symlink, etc.):
#   ${BASH_SOURCE[0]} - Path to the script as invoked
#   dirname           - Extract directory portion
#   cd ... && pwd     - Resolve to absolute path
#
# This is essential because the script needs to find the terraform directory
# relative to its own location, not the user's current working directory.
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../infrastructure/terraform"

# ----------------------------------------------------------------------------
# TERMINAL COLOR CODES
# ----------------------------------------------------------------------------
# ANSI escape codes for colored output improve readability in terminal:
#   BOLD   - Emphasize headers and important information
#   GREEN  - Success messages (operations completed successfully)
#   YELLOW - Progress indicators and warnings
#   RED    - Error messages and failures
#   NC     - "No Color" - reset to default terminal color
#
# Using colors helps users quickly scan output and identify issues.
# The -e flag in echo interprets these escape sequences.
# ----------------------------------------------------------------------------
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Display script header
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  AKS Regulated Enterprise - Cluster Setup${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# ============================================================================
# STEP 1: PREREQUISITE VALIDATION
# ============================================================================
# Before attempting any infrastructure operations, we verify all required
# tools are installed. This prevents partial execution failures that could
# leave infrastructure in an inconsistent state.
#
# Why each tool is required:
#   az       - Azure CLI for authentication and AKS credential retrieval
#   terraform - Infrastructure as Code engine for deployment
#   kubectl  - Kubernetes CLI for cluster verification
#   helm     - Package manager for security tool installation (next script)
#
# The 'command -v' check is POSIX-compliant and works across shell types.
# We redirect stdout/stderr to /dev/null because we only care if it succeeds.
# ============================================================================
echo -e "${YELLOW}[1/6] Checking prerequisites...${NC}"
MISSING=()

# Check each tool and accumulate missing ones
# This allows us to report all missing tools at once rather than failing on the first
command -v az >/dev/null 2>&1 || MISSING+=("az (Azure CLI)")
command -v terraform >/dev/null 2>&1 || MISSING+=("terraform")
command -v kubectl >/dev/null 2>&1 || MISSING+=("kubectl")
command -v helm >/dev/null 2>&1 || MISSING+=("helm")

# If any tools are missing, report all of them and exit
# This is more user-friendly than failing one at a time
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${RED}Missing required tools:${NC}"
    for tool in "${MISSING[@]}"; do
        echo "  - ${tool}"
    done
    exit 1
fi
echo -e "${GREEN}  All prerequisites found${NC}"
echo ""

# ============================================================================
# STEP 2: AZURE AUTHENTICATION CHECK
# ============================================================================
# Azure operations require authentication. We verify the user is logged in
# before proceeding to avoid cryptic errors during Terraform operations.
#
# 'az account show' returns the active subscription details if logged in,
# or fails with exit code 1 if not authenticated.
#
# Displaying the account name provides confirmation the user is working
# with the intended subscription (important when users have multiple).
# ============================================================================
echo -e "${YELLOW}[2/6] Checking Azure authentication...${NC}"
if ! az account show >/dev/null 2>&1; then
    echo -e "${RED}Not logged in to Azure. Run: az login${NC}"
    exit 1
fi
# Extract just the subscription name using JMESPath query
ACCOUNT=$(az account show --query name -o tsv)
echo -e "${GREEN}  Logged in to: ${ACCOUNT}${NC}"
echo ""

# ============================================================================
# STEP 3: TERRAFORM CONFIGURATION CHECK
# ============================================================================
# Terraform requires a terraform.tfvars file with site-specific values like:
#   - Resource group name and location
#   - Cluster name and node configuration
#   - Network settings
#
# Rather than fail with confusing Terraform errors about missing variables,
# we check proactively and help the user create the file from the template.
#
# SECURITY NOTE: terraform.tfvars is in .gitignore because it may contain
# sensitive configuration. The example file provides safe defaults.
# ============================================================================
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

# ============================================================================
# STEP 4: TERRAFORM INITIALIZATION
# ============================================================================
# 'terraform init' prepares the working directory:
#   - Downloads required provider plugins (azurerm, random, etc.)
#   - Initializes the backend (local by default)
#   - Validates the configuration syntax
#
# The -upgrade flag ensures we get the latest compatible provider versions.
# This is important for security patches in providers.
#
# We pipe output to 'tail -1' to show only the final status message,
# reducing noise while keeping the user informed of success/failure.
# ============================================================================
echo -e "${YELLOW}[4/6] Initializing Terraform... (this may take a minute)${NC}"
cd "${TERRAFORM_DIR}"
terraform init -upgrade 2>&1 | tail -1
echo -e "${GREEN}  Terraform initialized${NC}"
echo ""

# ============================================================================
# STEP 5: TERRAFORM PLAN (DRY RUN)
# ============================================================================
# 'terraform plan' is a DRY RUN that shows what would change without
# making any actual modifications. This is critical for:
#   - Reviewing changes before they happen
#   - Catching configuration errors
#   - Understanding cost implications
#
# The -out=tfplan flag saves the plan to a file. This ensures the apply
# step executes exactly what was reviewed, preventing race conditions
# where the infrastructure might change between plan and apply.
#
# INTERACTIVE CONFIRMATION: We require the user to type 'yes' to proceed.
# This follows the principle of least surprise for infrastructure changes.
# ============================================================================
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

# ============================================================================
# STEP 6: TERRAFORM APPLY (INFRASTRUCTURE CREATION)
# ============================================================================
# This step actually creates the Azure resources. The tfplan file ensures
# we apply exactly what was shown in the plan.
#
# TIMING: AKS cluster creation typically takes 5-10 minutes. The bulk of
# this time is Azure provisioning the control plane and node pools.
#
# After completion, we remove the tfplan file as it's no longer needed
# and may contain sensitive information about the planned resources.
# ============================================================================
echo -e "${YELLOW}[6/6] Applying infrastructure... (this takes 5-10 minutes)${NC}"
terraform apply tfplan 2>&1 | tail -10
rm -f tfplan
echo ""

# ============================================================================
# KUBECTL CONFIGURATION
# ============================================================================
# After the cluster is created, we need to configure kubectl to connect.
# 'az aks get-credentials' does this by:
#   - Fetching the cluster's kubeconfig from Azure
#   - Merging it into ~/.kube/config
#   - Setting it as the current context
#
# --overwrite-existing prevents prompts if this cluster was configured before.
#
# We retrieve the resource group and cluster names from Terraform outputs
# to ensure consistency with what was actually deployed.
# ============================================================================
echo -e "${YELLOW}Configuring kubectl...${NC}"
RG=$(terraform output -raw resource_group_name)
CLUSTER=$(terraform output -raw aks_cluster_name)
az aks get-credentials --resource-group "${RG}" --name "${CLUSTER}" --admin --overwrite-existing
echo ""

# ============================================================================
# CONNECTION VERIFICATION
# ============================================================================
# Finally, we verify the connection works by listing nodes. This confirms:
#   - kubectl is properly configured
#   - Network connectivity to the cluster exists
#   - Authentication is working
#
# If this fails, the user knows immediately rather than discovering issues
# when running the next script.
# ============================================================================
echo -e "${YELLOW}Verifying cluster connection...${NC}"
kubectl get nodes
echo ""

echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}  Cluster setup complete!${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "Next step: Install tools"
echo "  ./install-tools.sh"
