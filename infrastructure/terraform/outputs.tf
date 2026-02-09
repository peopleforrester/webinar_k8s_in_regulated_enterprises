# ==============================================================================
# TERRAFORM OUTPUTS - EXPORTED VALUES
# ==============================================================================
#
# PURPOSE:
# This file defines outputs that expose important information about the
# deployed infrastructure. Outputs serve multiple purposes:
#
# 1. HUMAN REFERENCE:
#    After deployment, outputs show key connection details like cluster names,
#    endpoints, and configuration commands.
#
# 2. AUTOMATION INTEGRATION:
#    CI/CD pipelines and scripts can query these values using:
#    terraform output -json
#    terraform output <output_name>
#
# 3. MODULE COMPOSITION:
#    When this configuration is used as a module, parent configurations
#    can reference these outputs for connecting dependent resources.
#
# OUTPUT CATEGORIES IN THIS FILE:
# - Resource Identifiers: Names and IDs for Azure resources
# - Connection Information: Endpoints and URIs for services
# - Security Outputs: Sensitive data marked appropriately
# - Operational Commands: Helper commands for cluster access
#
# SECURITY CONSIDERATIONS:
# - Sensitive outputs (like kube_config) are marked sensitive = true
# - Sensitive values are hidden in CLI output but accessible programmatically
# - Consider who has access to Terraform state (contains all outputs)
# - For production, use remote state with access controls
#
# REGULATORY ALIGNMENT:
# - NCUA: Audit trail through infrastructure documentation
# - OSFI B-13: Configuration management and documentation
# - DORA: ICT asset inventory and documentation
# ==============================================================================

# =============================================================================
# RESOURCE GROUP OUTPUTS
# =============================================================================
# The resource group is the top-level container for all deployed resources.
# These outputs help identify and manage the deployment.
# =============================================================================

output "resource_group_name" {
  description = "Name of the resource group containing all AKS resources"
  value       = azurerm_resource_group.main.name

  # USAGE EXAMPLES:
  # - Azure CLI: az group show --name <value>
  # - Azure Portal: Navigate to resource groups and search for this name
  # - Cost analysis: Filter costs by resource group
}

# =============================================================================
# AKS CLUSTER OUTPUTS
# =============================================================================
# These outputs provide the essential information needed to connect to
# and manage the AKS cluster.
# =============================================================================

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name

  # USAGE:
  # - Identify the cluster in Azure Portal
  # - Reference in Azure CLI commands
  # - Use in CI/CD pipeline configurations
}

output "aks_cluster_id" {
  description = "Azure Resource ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id

  # USAGE:
  # - Role assignments scoped to the cluster
  # - Azure Policy assignments
  # - Diagnostic settings configuration
  # - Cross-resource references in ARM/Terraform
  #
  # FORMAT:
  # /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.ContainerService/managedClusters/{name}
}

output "kube_config" {
  description = "Kubernetes configuration for kubectl (contains credentials)"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw

  # ---------------------------------------------------------------------------
  # SENSITIVE FLAG
  # ---------------------------------------------------------------------------
  # This output contains credentials that can be used to access the cluster.
  # The sensitive flag:
  # - Hides the value in terraform plan/apply output
  # - Still accessible via terraform output -raw kube_config
  # - Stored in plain text in Terraform state
  #
  # SECURITY BEST PRACTICES:
  # 1. Don't store this output in files or logs
  # 2. Use 'az aks get-credentials' command instead when possible
  # 3. Enable Azure AD authentication for user access
  # 4. Use workload identity for application access
  #
  # WHEN TO USE THIS OUTPUT:
  # - Initial CI/CD pipeline setup
  # - Automated testing that needs cluster access
  # - Emergency access when Azure AD is unavailable
  # ---------------------------------------------------------------------------
  sensitive = true
}

# =============================================================================
# KEY VAULT OUTPUTS
# =============================================================================
# Information needed to configure applications to use Key Vault for secrets.
# =============================================================================

output "key_vault_name" {
  description = "Name of the Key Vault for secrets management"
  value       = azurerm_key_vault.main.name

  # USAGE:
  # - Azure CLI: az keyvault secret list --vault-name <value>
  # - SecretProviderClass configuration in Kubernetes
  # - CI/CD pipeline secret retrieval
}

output "key_vault_uri" {
  description = "URI of the Key Vault (https://<name>.vault.azure.net/)"
  value       = azurerm_key_vault.main.vault_uri

  # USAGE:
  # - Application configuration for direct Key Vault SDK access
  # - SecretProviderClass keyvaultName field
  # - Workload Identity configuration
  #
  # FORMAT:
  # https://<vault-name>.vault.azure.net/
}

# =============================================================================
# CONTAINER REGISTRY OUTPUTS
# =============================================================================
# Information needed for pushing and pulling container images.
# =============================================================================

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name

  # USAGE:
  # - Azure CLI: az acr login --name <value>
  # - Docker: docker login <login_server>
  # - CI/CD: Reference in build pipelines
}

output "acr_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server

  # USAGE:
  # - Docker: docker login <value>
  # - Image tagging: docker tag myapp:latest <value>/myapp:latest
  # - Kubernetes manifests: image: <value>/myapp:latest
  #
  # FORMAT:
  # <registry-name>.azurecr.io
  #
  # EXAMPLE:
  # acraksregulateddemoab12cd.azurecr.io
}

# =============================================================================
# MONITORING OUTPUTS
# =============================================================================
# Information about the Log Analytics workspace for monitoring integration.
# =============================================================================

output "log_analytics_workspace_id" {
  description = "Azure Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id

  # USAGE:
  # - Additional diagnostic settings configuration
  # - Azure Monitor alert rules
  # - Workbook and dashboard references
  # - Cross-resource log queries
  #
  # FORMAT:
  # /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.OperationalInsights/workspaces/{name}
}

# =============================================================================
# WORKLOAD IDENTITY OUTPUTS
# =============================================================================
# Information needed for configuring workload identity for applications.
# =============================================================================

output "oidc_issuer_url" {
  description = "OIDC issuer URL for configuring workload identity federation"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url

  # ---------------------------------------------------------------------------
  # WHAT IS THIS?
  # ---------------------------------------------------------------------------
  # The OIDC issuer URL is an endpoint that Azure AD trusts for token exchange.
  # When you create a federated credential in Azure AD, you specify this URL
  # as the trusted issuer.
  #
  # HOW WORKLOAD IDENTITY WORKS:
  # 1. Pod has a Kubernetes service account
  # 2. Pod requests a token from the OIDC issuer
  # 3. Azure AD validates the token (trusts this issuer)
  # 4. Azure AD issues an access token for the requested resource
  # 5. Pod uses the Azure AD token to access Azure services
  #
  # USAGE:
  # When creating a federated credential in Azure AD:
  #
  # az identity federated-credential create \
  #   --name "my-app-credential" \
  #   --identity-name "my-app-identity" \
  #   --resource-group <rg> \
  #   --issuer "<this-output-value>" \
  #   --subject "system:serviceaccount:my-namespace:my-service-account" \
  #   --audiences "api://AzureADTokenExchange"
  #
  # FORMAT:
  # https://oidc.prod-aks.azure.com/{tenant-id}/{cluster-id}/
  # ---------------------------------------------------------------------------
}

# =============================================================================
# OPERATIONAL COMMANDS
# =============================================================================
# Helper outputs that provide ready-to-use commands for common operations.
# =============================================================================

output "get_credentials_command" {
  description = "Azure CLI command to configure kubectl for this cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name} --admin"

  # ---------------------------------------------------------------------------
  # WHAT THIS COMMAND DOES:
  # ---------------------------------------------------------------------------
  # 1. Retrieves the kubeconfig from Azure
  # 2. Merges it into your local ~/.kube/config file
  # 3. Sets the current context to this cluster
  #
  # AZURE AD AUTHENTICATION:
  # Because azure_rbac_enabled is true, this command will configure kubectl
  # to use Azure AD authentication. When you run kubectl commands:
  # - You'll be prompted to authenticate via browser
  # - Your Azure AD identity is used for RBAC
  # - No static credentials are stored
  #
  # VARIATIONS:
  #
  # # Admin credentials (bypasses Azure AD):
  # az aks get-credentials --resource-group <rg> --name <name> --admin
  #
  # # Overwrite existing config (don't merge):
  # az aks get-credentials --resource-group <rg> --name <name> --overwrite-existing
  #
  # # Output to specific file:
  # az aks get-credentials --resource-group <rg> --name <name> --file ./kubeconfig
  #
  # SECURITY NOTE:
  # Avoid using --admin in production. Admin credentials:
  # - Bypass Azure AD RBAC
  # - Have full cluster access
  # - Should only be used for emergency access
  # - Generate audit entries but without user identity
  # ---------------------------------------------------------------------------
}

# =============================================================================
# ADDITIONAL OUTPUTS (Examples for Production)
# =============================================================================
# Consider adding these outputs for production deployments:
#
# # Cluster API Server URL (for external tools)
# output "aks_api_server_url" {
#   description = "URL of the Kubernetes API server"
#   value       = azurerm_kubernetes_cluster.main.fqdn
# }
#
# # Network Information (for peering/firewall rules)
# output "vnet_id" {
#   description = "ID of the virtual network"
#   value       = azurerm_virtual_network.main.id
# }
#
# output "aks_subnet_id" {
#   description = "ID of the AKS subnet"
#   value       = azurerm_subnet.aks.id
# }
#
# # Identity Information (for role assignments)
# output "aks_identity_principal_id" {
#   description = "Principal ID of the AKS managed identity"
#   value       = azurerm_user_assigned_identity.aks.principal_id
# }
#
# output "kubelet_identity_object_id" {
#   description = "Object ID of the kubelet identity"
#   value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
# }
#
# # Node Resource Group (Azure creates this automatically)
# output "node_resource_group" {
#   description = "Name of the auto-created resource group for AKS nodes"
#   value       = azurerm_kubernetes_cluster.main.node_resource_group
# }
# =============================================================================
