# ABOUTME: Azure managed identity and federated credential for Crossplane Azure providers.
# ABOUTME: Enables Crossplane to manage Azure resources via workload identity (no secrets).
# ==============================================================================
# CROSSPLANE IDENTITY AND FEDERATION
# ==============================================================================
#
# PURPOSE:
# Crossplane Azure providers need permission to manage Azure resources.
# This file creates a managed identity and links it to the Crossplane
# provider's Kubernetes service account via federated credentials (OIDC).
#
# ARCHITECTURE:
# ┌─────────────────────┐     ┌─────────────────────┐
# │ Crossplane Provider │     │ Azure AD             │
# │ (in-cluster pod)    │     │                      │
# │                     │     │  Managed Identity:   │
# │  K8s ServiceAccount ├────►│  id-crossplane-...   │
# │  + projected token  │     │                      │
# └─────────────────────┘     │  Federated Cred:     │
#                              │  crossplane-provider │
#                              └──────────┬───────────┘
#                                         │
#                              Azure RBAC roles:
#                              - Contributor (RG scoped)
#
# REGULATORY CONTEXT:
#   - SOC 2 CC6.1: Identity-based access via workload identity
#   - NCUA Part 748: No shared or static credentials
#   - DORA Article 9: Automated identity lifecycle management
# ==============================================================================

# -----------------------------------------------------------------------------
# MANAGED IDENTITY FOR CROSSPLANE
# -----------------------------------------------------------------------------
# A separate identity for Crossplane ensures blast radius isolation.
# If the Crossplane identity is compromised, it only affects resources
# within its RBAC scope, not the AKS cluster itself.
# -----------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "crossplane" {
  name                = "id-crossplane-${var.cluster_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# ROLE ASSIGNMENT: Contributor on Resource Group
# -----------------------------------------------------------------------------
# Crossplane needs permissions to create and manage Azure resources.
# Scoped to the resource group (not the subscription) for least privilege.
#
# For production, consider scoping to specific resource types using
# custom roles instead of the broad Contributor role.
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "crossplane_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.crossplane.principal_id
}

# -----------------------------------------------------------------------------
# FEDERATED IDENTITY CREDENTIAL
# -----------------------------------------------------------------------------
# Links the Kubernetes ServiceAccount used by the Crossplane Azure provider
# to the Azure managed identity. This allows the provider pod to exchange
# its projected service account token for an Azure AD access token.
#
# The subject must match the exact service account name and namespace
# that the Crossplane Azure provider runs under.
# -----------------------------------------------------------------------------
resource "azurerm_federated_identity_credential" "crossplane_provider" {
  name                = "crossplane-provider"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.crossplane.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url

  # The subject is the K8s service account that Crossplane Azure provider uses.
  # Format: system:serviceaccount:<namespace>:<service-account-name>
  # The provider SA name follows the pattern: <provider-name>-<hash>
  # Using wildcard-compatible subject for the provider family controller.
  subject = "system:serviceaccount:crossplane-system:crossplane"
}

# -----------------------------------------------------------------------------
# OUTPUTS
# -----------------------------------------------------------------------------
output "crossplane_identity_client_id" {
  description = "Client ID for Crossplane ProviderConfig (replace placeholder in provider.yaml)"
  value       = azurerm_user_assigned_identity.crossplane.client_id
}

output "crossplane_identity_principal_id" {
  description = "Principal ID of the Crossplane managed identity"
  value       = azurerm_user_assigned_identity.crossplane.principal_id
}
