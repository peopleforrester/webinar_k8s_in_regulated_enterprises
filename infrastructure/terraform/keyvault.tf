# ==============================================================================
# AZURE KEY VAULT CONFIGURATION
# ==============================================================================
#
# PURPOSE:
# This file configures Azure Key Vault for secure secrets management, providing
# a centralized, secure store for sensitive data used by AKS workloads.
#
# WHY KEY VAULT FOR REGULATED ENTERPRISES:
# ┌──────────────────────────────────────────────────────────────────────────────┐
# │ Capability                 │ Regulatory Benefit                             │
# ├──────────────────────────────────────────────────────────────────────────────┤
# │ Hardware Security Modules  │ FIPS 140-2 Level 2 validated (Premium SKU)     │
# │ Access Policies/RBAC       │ Granular control over who can access what      │
# │ Audit Logging              │ Complete trail of secret access attempts       │
# │ Soft Delete                │ Protect against accidental deletion            │
# │ Purge Protection           │ Prevent permanent deletion (for compliance)    │
# │ Network Isolation          │ VNet integration, private endpoints            │
# │ Secret Versioning          │ Track changes, rollback capability             │
# │ Automatic Rotation         │ Integrate with Azure services for rotation     │
# └──────────────────────────────────────────────────────────────────────────────┘
#
# INTEGRATION WITH AKS:
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                                                                              │
# │    Pod with CSI Volume                    Azure Key Vault                    │
# │    ┌─────────────────────┐                ┌────────────────────┐           │
# │    │ App Container       │                │  Secrets:          │           │
# │    │ ┌─────────────────┐ │                │  - db-password     │           │
# │    │ │ /mnt/secrets/   │ │◀── Mounted ───│  - api-key         │           │
# │    │ │   db-password   │ │    as files   │  - connection-str  │           │
# │    │ │   api-key       │ │                │                    │           │
# │    │ └─────────────────┘ │                │  Uses Workload     │           │
# │    └─────────────────────┘                │  Identity          │           │
# │                                            └────────────────────┘           │
# │    SecretProviderClass                                                      │
# │    ┌─────────────────────┐                                                  │
# │    │ Defines which       │                                                  │
# │    │ secrets to mount    │                                                  │
# │    └─────────────────────┘                                                  │
# │                                                                              │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# REGULATORY ALIGNMENT:
# - NCUA Part 748: Secure storage of sensitive data
# - OSFI B-13: Cryptographic key management
# - DORA Article 9: ICT security policies for secrets
# - PCI DSS 3.5-3.6: Cryptographic key protection
#
# 2026 FEATURES:
# - Workload Identity integration (no secrets in cluster)
# - CSI driver with automatic rotation
# - Azure Policy integration for compliance
# ==============================================================================

# =============================================================================
# KEY VAULT RESOURCE
# =============================================================================
# Azure Key Vault provides secure storage for:
# - Secrets: Connection strings, API keys, passwords
# - Keys: Cryptographic keys for encryption/decryption
# - Certificates: TLS certificates with auto-renewal
#
# This configuration focuses on secrets for AKS workloads, but the same
# vault can manage keys and certificates as needed.
# =============================================================================
resource "azurerm_key_vault" "main" {
  # ---------------------------------------------------------------------------
  # VAULT NAME
  # ---------------------------------------------------------------------------
  # Globally unique name (forms the vault URI).
  # Format: https://<name>.vault.azure.net/
  #
  # Naming constraints:
  # - 3-24 characters
  # - Alphanumeric and hyphens only
  # - Must start with a letter
  # - Must be globally unique
  # ---------------------------------------------------------------------------
  name                = "kv-${var.cluster_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # ---------------------------------------------------------------------------
  # TENANT ID
  # ---------------------------------------------------------------------------
  # The Entra ID (Azure AD) tenant that owns this Key Vault.
  # All access policies and RBAC assignments are relative to this tenant.
  #
  # Retrieved from the current Azure context using the data source.
  # ---------------------------------------------------------------------------
  tenant_id = data.azurerm_client_config.current.tenant_id

  # ---------------------------------------------------------------------------
  # SKU (PRICING TIER)
  # ---------------------------------------------------------------------------
  # Key Vault offers two SKUs:
  #
  # STANDARD:
  # - Software-protected keys
  # - Secrets and certificates
  # - Suitable for most workloads
  # - Lower cost
  #
  # PREMIUM:
  # - HSM-protected keys (FIPS 140-2 Level 2)
  # - All Standard features
  # - Required for some compliance requirements
  # - Higher cost
  #
  # FOR REGULATED ENVIRONMENTS:
  # Consider Premium if:
  # - Regulatory requirements mandate HSM protection
  # - Handling cryptographic keys for encryption at rest
  # - PCI DSS or similar compliance requirements
  # ---------------------------------------------------------------------------
  sku_name = "standard"

  # ---------------------------------------------------------------------------
  # DISK ENCRYPTION
  # ---------------------------------------------------------------------------
  # Allows this Key Vault to be used for Azure Disk Encryption.
  # Required if you want to use customer-managed keys for:
  # - OS disk encryption on AKS nodes
  # - Persistent volume encryption
  # - Virtual machine disk encryption
  #
  # NOTE: Enabling this doesn't automatically encrypt anything;
  # it just allows the vault to be used for that purpose.
  # ---------------------------------------------------------------------------
  enabled_for_disk_encryption = true

  # ---------------------------------------------------------------------------
  # SOFT DELETE AND PURGE PROTECTION
  # ---------------------------------------------------------------------------
  # Soft Delete: When a vault or object is deleted, it's retained for a
  # recovery period before permanent deletion.
  #
  # SOFT DELETE RETENTION:
  # - 7-90 days (default: 90)
  # - Set to 7 for demo/development (faster cleanup)
  # - Set to 90 for production (maximum protection)
  #
  # PURGE PROTECTION:
  # - When enabled, deleted objects CANNOT be permanently purged
  # - Must wait for retention period to expire
  # - Provides protection against malicious deletion
  #
  # CURRENT CONFIGURATION:
  # - soft_delete_retention_days = 7 (demo setting)
  # - purge_protection_enabled = false (allows cleanup)
  #
  # FOR PRODUCTION:
  # Set purge_protection_enabled = true
  # This is REQUIRED for some compliance scenarios (e.g., key-based encryption)
  # and CANNOT be disabled once enabled.
  #
  # REGULATORY ALIGNMENT:
  # - NCUA: Data protection and retention
  # - OSFI B-13: Backup and recovery requirements
  # - DORA: Data integrity and availability
  # ---------------------------------------------------------------------------
  purge_protection_enabled   = false # Set to true for production
  soft_delete_retention_days = 7

  # ---------------------------------------------------------------------------
  # NETWORK ACCESS RULES
  # ---------------------------------------------------------------------------
  # Controls network access to the Key Vault.
  #
  # DEFAULT ACTION: Deny
  # All traffic is blocked unless explicitly allowed.
  # This is a critical security control for regulated environments.
  #
  # BYPASS: AzureServices
  # Allows trusted Azure services to access the vault even when
  # default_action is Deny. Includes:
  # - Azure Backup
  # - Azure Site Recovery
  # - Azure Disk Encryption
  # - Azure Resource Manager (for ARM templates)
  #
  # VIRTUAL NETWORK RULES:
  # Only the AKS subnet can access this Key Vault over the network.
  # Combined with service endpoint on the subnet (see networking.tf),
  # this ensures traffic stays on the Azure backbone.
  #
  # FOR ENHANCED SECURITY (Premium SKU):
  # Use private endpoints instead of/in addition to VNet rules:
  # - No public IP exposure
  # - DNS resolution to private IP
  # - Traffic never leaves the VNet
  # ---------------------------------------------------------------------------
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"

    # Only allow access from the AKS subnet
    virtual_network_subnet_ids = [azurerm_subnet.aks.id]

    # To allow access from specific IPs (e.g., CI/CD or admin):
    # ip_rules = ["203.0.113.0/24"]
  }

  tags = var.tags
}

# =============================================================================
# ACCESS POLICY - AKS SECRETS PROVIDER
# =============================================================================
# Grants the Key Vault CSI driver permission to read secrets.
#
# HOW THE CSI DRIVER AUTHENTICATES:
# The Key Vault CSI driver uses a system-assigned managed identity
# that's created when you enable key_vault_secrets_provider on the cluster.
# This identity is separate from:
# - The user-assigned identity we created for cluster management
# - The kubelet identity used for ACR access
# - Any workload identities for your applications
#
# PERMISSION SCOPE:
# - Get: Read individual secret values
# - List: Enumerate secret names (for wildcard mounts)
#
# These are the minimum permissions needed for the CSI driver to function.
# The driver doesn't need Set, Delete, or other permissions.
#
# ACCESS POLICY VS RBAC:
# This uses the legacy access policy model. For new deployments, consider:
# - Azure RBAC for Key Vault (enable_rbac_authorization = true)
# - More granular permissions
# - Consistent with Azure RBAC for other resources
# - Easier to manage at scale with Entra ID groups
# =============================================================================
resource "azurerm_key_vault_access_policy" "aks" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id

  # ---------------------------------------------------------------------------
  # PRINCIPAL (IDENTITY)
  # ---------------------------------------------------------------------------
  # The CSI driver's identity is exposed via the key_vault_secrets_provider
  # block on the AKS cluster resource.
  #
  # IDENTITY CHAIN:
  # AKS Cluster
  #   └─> key_vault_secrets_provider[0]
  #       └─> secret_identity[0]
  #           └─> object_id (the Entra ID principal ID)
  # ---------------------------------------------------------------------------
  object_id = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].object_id

  # ---------------------------------------------------------------------------
  # SECRET PERMISSIONS
  # ---------------------------------------------------------------------------
  # Minimum permissions for the CSI driver:
  # - Get: Retrieve secret values
  # - List: Enumerate secrets (needed for wildcard SecretProviderClass)
  #
  # NOT INCLUDED (not needed by CSI driver):
  # - Set: Create or update secrets
  # - Delete: Remove secrets
  # - Backup/Restore: Backup operations
  # - Recover: Recover soft-deleted secrets
  # - Purge: Permanently delete secrets
  # ---------------------------------------------------------------------------
  secret_permissions = [
    "Get",
    "List"
  ]
}

# =============================================================================
# ACCESS POLICY - CURRENT USER (DEPLOYMENT)
# =============================================================================
# Grants the identity running Terraform permission to manage secrets.
# This is needed for:
# - Initial secret population during deployment
# - Manual secret management by administrators
# - CI/CD pipeline secret updates
#
# SECURITY CONSIDERATIONS:
# - This grants broad permissions to the deploying identity
# - For production, consider using separate identities for:
#   - Infrastructure deployment (Contributor, no Key Vault data access)
#   - Secret management (Key Vault Administrator)
# - Use Privileged Identity Management (PIM) for just-in-time access
#
# PERMISSIONS GRANTED:
# - Get: Read secret values
# - List: Enumerate secrets
# - Set: Create or update secrets
# - Delete: Soft-delete secrets
# - Purge: Permanently delete secrets (if purge protection disabled)
#
# NOTE: These permissions apply to the identity running 'terraform apply'.
# In CI/CD, this would be a service principal.
# For manual deployment, this would be the logged-in user.
# =============================================================================
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id

  # ---------------------------------------------------------------------------
  # PRINCIPAL (IDENTITY)
  # ---------------------------------------------------------------------------
  # The object_id of whoever is running Terraform.
  # This is automatically populated from the Azure context.
  # ---------------------------------------------------------------------------
  object_id = data.azurerm_client_config.current.object_id

  # ---------------------------------------------------------------------------
  # SECRET PERMISSIONS
  # ---------------------------------------------------------------------------
  # Full secret management permissions for initial setup and administration.
  #
  # FOR PRODUCTION:
  # - Consider removing Purge if purge_protection is enabled
  # - Use separate access policies for different admin roles
  # - Implement approval workflows for sensitive operations
  # ---------------------------------------------------------------------------
  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge"
  ]
}

# =============================================================================
# ADDITIONAL ACCESS POLICIES (Examples for Production)
# =============================================================================
# For production environments, you may need additional access policies:
#
# # Application Identity (Workload Identity)
# # When applications authenticate directly to Key Vault
# resource "azurerm_key_vault_access_policy" "app" {
#   key_vault_id = azurerm_key_vault.main.id
#   tenant_id    = data.azurerm_client_config.current.tenant_id
#   object_id    = azuread_service_principal.app.object_id
#
#   secret_permissions = ["Get"]
# }
#
# # Security Team (Read-Only)
# # For audit and compliance verification
# resource "azurerm_key_vault_access_policy" "security" {
#   key_vault_id = azurerm_key_vault.main.id
#   tenant_id    = data.azurerm_client_config.current.tenant_id
#   object_id    = azuread_group.security_team.object_id
#
#   secret_permissions = ["Get", "List"]
#   key_permissions    = ["Get", "List"]
# }
#
# # Backup Service
# # For Key Vault backup operations
# resource "azurerm_key_vault_access_policy" "backup" {
#   key_vault_id = azurerm_key_vault.main.id
#   tenant_id    = data.azurerm_client_config.current.tenant_id
#   object_id    = azuread_service_principal.backup.object_id
#
#   secret_permissions = ["Backup", "Get", "List"]
#   key_permissions    = ["Backup", "Get", "List"]
# }
# =============================================================================

# =============================================================================
# DIAGNOSTIC SETTINGS (Recommended for Production)
# =============================================================================
# For compliance, enable diagnostic logging on Key Vault:
#
# resource "azurerm_monitor_diagnostic_setting" "keyvault" {
#   name                       = "diag-${azurerm_key_vault.main.name}"
#   target_resource_id         = azurerm_key_vault.main.id
#   log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
#
#   # Audit events (access attempts, policy changes)
#   enabled_log {
#     category = "AuditEvent"
#   }
#
#   # Azure Policy audit events
#   enabled_log {
#     category = "AzurePolicyEvaluationDetails"
#   }
#
#   # All metrics
#   metric {
#     category = "AllMetrics"
#     enabled  = true
#   }
# }
#
# This captures:
# - All secret access attempts (success and failure)
# - Configuration changes
# - Policy evaluations
# - Performance metrics
#
# REGULATORY ALIGNMENT:
# - NCUA: Audit trail for sensitive data access
# - OSFI B-13: Logging and monitoring requirements
# - DORA: ICT incident detection and response
# - PCI DSS 10: Audit trail requirements
# =============================================================================
