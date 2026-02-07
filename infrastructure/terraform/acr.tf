# ==============================================================================
# AZURE CONTAINER REGISTRY (ACR) CONFIGURATION
# ==============================================================================
#
# PURPOSE:
# This file configures Azure Container Registry, a managed Docker registry
# service for storing and managing container images used by the AKS cluster.
#
# WHY ACR FOR REGULATED ENTERPRISES:
# ┌──────────────────────────────────────────────────────────────────────────────┐
# │ Feature                    │ Regulatory Benefit                              │
# ├──────────────────────────────────────────────────────────────────────────────┤
# │ Private Registry           │ Images never traverse public networks           │
# │ Azure AD Authentication    │ No shared credentials, audit trail              │
# │ Geo-replication           │ Images available in DR regions                   │
# │ Content Trust             │ Sign images to verify integrity                  │
# │ Vulnerability Scanning    │ Identify CVEs before deployment                  │
# │ Retention Policies        │ Automatic cleanup of old images                  │
# │ Network Isolation         │ Private endpoint and service endpoint support    │
# └──────────────────────────────────────────────────────────────────────────────┘
#
# ARCHITECTURE:
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                                                                              │
# │    CI/CD Pipeline                    Azure Container Registry                │
# │    ┌─────────────┐                   ┌────────────────────────┐            │
# │    │   Build     │──── docker push ──▶│  Repository            │            │
# │    │   Image     │                   │  ┌─────────────────┐   │            │
# │    └─────────────┘                   │  │ app:v1.0.0      │   │            │
# │                                       │  │ app:v1.0.1      │   │            │
# │                                       │  │ app:latest      │   │            │
# │    AKS Cluster                       │  └─────────────────┘   │            │
# │    ┌─────────────┐                   │                        │            │
# │    │   kubelet   │◀── docker pull ───│  Uses Managed Identity │            │
# │    │  (on node)  │   (AcrPull role)  │  for authentication    │            │
# │    └─────────────┘                   └────────────────────────┘            │
# │                                                                              │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# REGULATORY ALIGNMENT:
# - NCUA Part 748: Secure software development and deployment
# - OSFI B-13: Third-party software management
# - DORA Article 6: ICT security in software development
#
# 2026 INTEGRATION:
# - Works with Image Cleaner to remove vulnerable images from nodes
# - Supports Workload Identity for secure push operations
# - Integrates with Microsoft Defender for vulnerability scanning
# ==============================================================================

# =============================================================================
# AZURE CONTAINER REGISTRY
# =============================================================================
# The container registry stores Docker images for AKS workloads.
#
# NAMING:
# ACR names must be globally unique (forms the login server URL).
# Format: <name>.azurecr.io
# Example: acraksregulateddemoabc123.azurecr.io
#
# We remove hyphens from the cluster name because ACR names can only
# contain alphanumeric characters.
# =============================================================================
resource "azurerm_container_registry" "main" {
  # ---------------------------------------------------------------------------
  # REGISTRY NAME
  # ---------------------------------------------------------------------------
  # Globally unique name for the registry.
  # - "acr" prefix identifies this as a container registry
  # - Cluster name (without hyphens) provides context
  # - Random suffix ensures global uniqueness
  #
  # EXAMPLE RESULT: acraksregulateddemoab12cd
  # LOGIN SERVER: acraksregulateddemoab12cd.azurecr.io
  # ---------------------------------------------------------------------------
  name                = "acr${replace(var.cluster_name, "-", "")}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # ---------------------------------------------------------------------------
  # SKU (PRICING TIER)
  # ---------------------------------------------------------------------------
  # ACR offers three SKUs with different capabilities:
  #
  # BASIC ($0.167/day):
  # - 10 GB storage
  # - 10 webhooks
  # - No geo-replication
  # - No content trust
  #
  # STANDARD ($0.667/day) - SELECTED:
  # - 100 GB storage
  # - 100 webhooks
  # - No geo-replication
  # - No content trust
  # - Good balance for most workloads
  #
  # PREMIUM ($1.667/day):
  # - 500 GB storage (expandable)
  # - 500 webhooks
  # - Geo-replication (multi-region)
  # - Content trust (image signing)
  # - Private endpoints
  # - Customer-managed keys
  # - Token-based repository access
  #
  # FOR REGULATED PRODUCTION ENVIRONMENTS:
  # Consider Premium for:
  # - Private endpoints (no public access)
  # - Content trust (verify image integrity)
  # - Geo-replication (disaster recovery)
  # - Customer-managed encryption keys
  # ---------------------------------------------------------------------------
  sku = "Standard"

  # ---------------------------------------------------------------------------
  # ADMIN ACCOUNT
  # ---------------------------------------------------------------------------
  # The admin account provides username/password authentication to the registry.
  #
  # DISABLED (admin_enabled = false) BECAUSE:
  # - Admin credentials are shared (anyone with password has full access)
  # - No audit trail of who performed operations
  # - Credentials must be rotated manually
  # - Violates principle of least privilege
  #
  # INSTEAD, USE:
  # - Managed Identity (AKS kubelet identity with AcrPull role)
  # - Service Principals (for CI/CD with AcrPush role)
  # - Entra ID users (for developer access)
  #
  # REGULATORY ALIGNMENT:
  # - NCUA: Individual accountability through identity-based access
  # - OSFI B-13: Access control and audit requirements
  # - DORA: Authentication and access control policies
  #
  # WHEN ADMIN MIGHT BE NEEDED:
  # - Legacy systems that don't support Azure AD
  # - Third-party CI/CD tools without Azure integration
  # - Emergency access (enable temporarily, audit usage)
  # ---------------------------------------------------------------------------
  admin_enabled = false

  # ---------------------------------------------------------------------------
  # ADDITIONAL SECURITY CONFIGURATIONS (For Premium SKU)
  # ---------------------------------------------------------------------------
  # The following configurations are available with Premium SKU:
  #
  # # Private endpoint (blocks public access):
  # public_network_access_enabled = false
  #
  # # Network rules (restrict access to specific networks):
  # network_rule_set {
  #   default_action = "Deny"
  #   virtual_network {
  #     action    = "Allow"
  #     subnet_id = azurerm_subnet.aks.id
  #   }
  # }
  #
  # # Content trust (image signing):
  # trust_policy {
  #   enabled = true
  # }
  #
  # # Retention policy (auto-delete untagged manifests):
  # retention_policy {
  #   days    = 7
  #   enabled = true
  # }
  #
  # # Quarantine policy (hold images for scanning):
  # quarantine_policy_enabled = true
  # ---------------------------------------------------------------------------

  tags = var.tags
}

# =============================================================================
# ACR ROLE ASSIGNMENT - AKS IMAGE PULL
# =============================================================================
# Grants the AKS cluster permission to pull images from this registry.
#
# HOW AKS AUTHENTICATES TO ACR:
# 1. Each AKS node has a "kubelet identity" (system-assigned managed identity)
# 2. This identity is automatically created when AKS is deployed
# 3. We grant this identity the "AcrPull" role on the registry
# 4. When kubelet pulls an image, it uses this identity to authenticate
# 5. No credentials are stored or transmitted
#
# SECURITY BENEFITS:
# - No imagePullSecrets needed in Kubernetes manifests
# - No registry credentials stored in the cluster
# - Identity is automatically rotated by Azure
# - Audit trail in Entra ID and ACR logs
#
# ROLE: AcrPull
# Allows:
# - Pull images from the registry
# - List repositories and tags
# Does NOT allow:
# - Push images (use AcrPush for CI/CD)
# - Delete images (use AcrDelete or Contributor)
# - Manage registry settings
#
# SCOPE: Registry level
# The AKS identity can pull any image from any repository in this registry.
# For more granular control (specific repositories), use repository-scoped
# tokens (Premium SKU required).
# =============================================================================
resource "azurerm_role_assignment" "aks_acr" {
  # ---------------------------------------------------------------------------
  # SCOPE
  # ---------------------------------------------------------------------------
  # Limited to this specific container registry.
  # The AKS identity cannot pull from other registries without additional
  # role assignments.
  # ---------------------------------------------------------------------------
  scope = azurerm_container_registry.main.id

  # ---------------------------------------------------------------------------
  # ROLE DEFINITION
  # ---------------------------------------------------------------------------
  # AcrPull is a built-in role specifically for pulling container images.
  #
  # OTHER ACR ROLES:
  # - AcrPush: Pull and push images (for CI/CD pipelines)
  # - AcrDelete: Delete images and repositories
  # - Contributor: Full management including registry settings
  # - Reader: View registry configuration only
  # ---------------------------------------------------------------------------
  role_definition_name = "AcrPull"

  # ---------------------------------------------------------------------------
  # PRINCIPAL (IDENTITY)
  # ---------------------------------------------------------------------------
  # The kubelet identity is a system-assigned managed identity created by AKS.
  # It's separate from the user-assigned identity we created for cluster
  # management (networking, load balancers, etc.).
  #
  # ACCESSING THE KUBELET IDENTITY:
  # The kubelet_identity block is exposed by the AKS resource after creation.
  # We reference the object_id (the Entra ID principal ID) for role assignment.
  #
  # NOTE: This creates an implicit dependency on the AKS cluster.
  # Terraform will create the cluster first, then create this role assignment.
  # ---------------------------------------------------------------------------
  principal_id = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# =============================================================================
# ADDITIONAL ROLE ASSIGNMENTS (Commented examples for production)
# =============================================================================
# For production environments, you may need additional role assignments:
#
# # CI/CD Pipeline Push Access
# # Grant a service principal permission to push images
# resource "azurerm_role_assignment" "cicd_acr" {
#   scope                = azurerm_container_registry.main.id
#   role_definition_name = "AcrPush"
#   principal_id         = azuread_service_principal.cicd.object_id
# }
#
# # Developer Read Access
# # Grant an Entra ID group permission to view the registry
# resource "azurerm_role_assignment" "dev_acr" {
#   scope                = azurerm_container_registry.main.id
#   role_definition_name = "Reader"
#   principal_id         = azuread_group.developers.object_id
# }
#
# # Cross-cluster Pull Access
# # Grant another AKS cluster permission to pull images
# resource "azurerm_role_assignment" "other_aks_acr" {
#   scope                = azurerm_container_registry.main.id
#   role_definition_name = "AcrPull"
#   principal_id         = azurerm_kubernetes_cluster.other.kubelet_identity[0].object_id
# }
# =============================================================================
