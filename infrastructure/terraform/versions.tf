# ==============================================================================
# TERRAFORM VERSION AND PROVIDER CONFIGURATION
# ==============================================================================
#
# PURPOSE:
# This file defines the Terraform version constraints and configures the Azure
# providers required for deploying AKS in regulated enterprise environments.
#
# WHY VERSION PINNING MATTERS FOR REGULATED ENTERPRISES:
# Financial regulators (NCUA, OSFI, DORA) require reproducible infrastructure
# deployments. Version pinning ensures:
# - Audit trail consistency: Same code produces same infrastructure
# - Change control compliance: Provider upgrades are deliberate, not accidental
# - Rollback capability: Known-good versions can be restored quickly
#
# REGULATORY ALIGNMENT:
# - NCUA Part 748: Requires documented change management processes
# - OSFI B-13: Mandates technology risk management including version control
# - DORA Article 9: Requires ICT asset management and configuration control
# ==============================================================================

terraform {
  # ---------------------------------------------------------------------------
  # TERRAFORM VERSION CONSTRAINT
  # ---------------------------------------------------------------------------
  # We require Terraform 1.6.0+ for several critical features:
  # - Improved provider plugin caching (faster CI/CD pipelines)
  # - Enhanced state locking mechanisms (prevents concurrent modifications)
  # - Better error messages for debugging infrastructure issues
  #
  # For production regulated environments, consider pinning to an exact version
  # (e.g., "= 1.6.6") to ensure complete reproducibility across team members
  # and CI/CD systems.
  # ---------------------------------------------------------------------------
  required_version = ">= 1.6.0"

  required_providers {
    # -------------------------------------------------------------------------
    # AZURE RESOURCE MANAGER PROVIDER (azurerm)
    # -------------------------------------------------------------------------
    # The primary provider for managing Azure infrastructure resources.
    #
    # Version ~> 3.85 means:
    # - Minimum version: 3.85.0
    # - Maximum version: < 4.0.0 (pessimistic constraint)
    #
    # WHY 3.85+:
    # - Full support for Kubernetes 1.34 features in AKS
    # - Cilium network data plane configuration
    # - Image Cleaner (Eraser) GA support
    # - AzureLinux node OS SKU
    # - Workload Identity improvements
    #
    # UPGRADE CONSIDERATION:
    # When azurerm 4.0 is released, review breaking changes carefully.
    # The 'managed' parameter in azure_active_directory_role_based_access_control
    # will become default and may be removed.
    # -------------------------------------------------------------------------
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }

    # -------------------------------------------------------------------------
    # AZURE ACTIVE DIRECTORY PROVIDER (azuread)
    # -------------------------------------------------------------------------
    # Used for managing Entra ID (formerly Azure AD) resources such as:
    # - Service principals for CI/CD pipelines
    # - Application registrations for workload identity
    # - Group management for Kubernetes RBAC
    #
    # REGULATORY CONTEXT:
    # Identity management is central to all financial regulations:
    # - NCUA requires strong authentication controls
    # - OSFI B-13 mandates identity governance
    # - DORA Article 9 requires access control management
    # -------------------------------------------------------------------------
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }

    # -------------------------------------------------------------------------
    # RANDOM PROVIDER
    # -------------------------------------------------------------------------
    # Generates random values for resource naming to ensure global uniqueness.
    #
    # WHY RANDOM SUFFIXES:
    # Azure resources like Key Vault and Container Registry require globally
    # unique names across all Azure tenants. A random suffix prevents:
    # - Naming collisions during disaster recovery to alternate regions
    # - Conflicts when multiple teams deploy similar infrastructure
    # - Issues when recreating resources after deletion (soft-delete conflicts)
    #
    # IMPORTANT: The random values are stored in Terraform state. Losing state
    # means you cannot manage existing resources with these names.
    # -------------------------------------------------------------------------
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# =============================================================================
# AZURE RESOURCE MANAGER PROVIDER CONFIGURATION
# =============================================================================
# Provider-level configuration affects all azurerm resources in this module.
#
# The 'features' block is required by azurerm (even if empty) and allows
# customization of provider behavior for specific resource types.
# =============================================================================
provider "azurerm" {
  features {
    # -------------------------------------------------------------------------
    # KEY VAULT FEATURE FLAGS
    # -------------------------------------------------------------------------
    # These settings control how Terraform handles Key Vault lifecycle events.
    #
    # purge_soft_delete_on_destroy = true
    # - When Terraform destroys a Key Vault, it will also purge it from
    #   soft-delete, making the name immediately available for reuse
    # - CAUTION FOR PRODUCTION: In regulated environments, you may want this
    #   set to 'false' to preserve deleted vaults for audit purposes
    # - Soft-deleted vaults are retained for the configured retention period
    #   (7-90 days) and can be recovered if needed
    #
    # recover_soft_deleted_key_vaults = true
    # - If Terraform tries to create a Key Vault with a name that exists in
    #   soft-delete, it will recover that vault instead of failing
    # - This prevents the common error: "Key Vault name already in use"
    # - Useful for development environments with frequent create/destroy cycles
    #
    # REGULATORY NOTE:
    # DORA and NCUA require data retention policies. For production, consider:
    # - Setting purge_soft_delete_on_destroy = false
    # - Implementing separate purge procedures with approval workflows
    # - Documenting the soft-delete retention period in your data governance
    # -------------------------------------------------------------------------
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }

  # ---------------------------------------------------------------------------
  # AUTHENTICATION
  # ---------------------------------------------------------------------------
  # The azurerm provider supports multiple authentication methods:
  #
  # 1. Azure CLI (default, used here)
  #    - Authenticates using 'az login' session
  #    - Suitable for development and interactive use
  #
  # 2. Service Principal with Client Secret
  #    - Set ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
  #    - Common for CI/CD pipelines
  #
  # 3. Managed Identity
  #    - Set ARM_USE_MSI = true
  #    - Best for Azure-hosted CI/CD agents (Azure DevOps, GitHub Actions)
  #
  # 4. OIDC (Workload Identity Federation)
  #    - Set ARM_USE_OIDC = true with ARM_OIDC_TOKEN
  #    - Recommended for GitHub Actions (no secrets to manage)
  #
  # REGULATORY BEST PRACTICE:
  # Use Managed Identity or OIDC for production deployments to avoid
  # storing credentials in CI/CD systems. This aligns with:
  # - NCUA requirements for credential management
  # - OSFI B-13 guidance on secrets handling
  # - DORA Article 9 on ICT security
  # ---------------------------------------------------------------------------
}

# =============================================================================
# AZURE ACTIVE DIRECTORY PROVIDER CONFIGURATION
# =============================================================================
# The azuread provider inherits authentication from the azurerm provider
# when no explicit configuration is provided.
#
# This provider is used to manage:
# - Service principals for AKS and ACR integration
# - Application registrations for workload identity
# - Entra ID groups for Kubernetes RBAC
#
# AUTHENTICATION NOTE:
# The identity running Terraform needs appropriate Entra ID permissions:
# - Application.ReadWrite.All: For creating service principals
# - Group.ReadWrite.All: For managing RBAC groups
# - Directory.Read.All: For reading directory objects
#
# Consider using a dedicated service principal with minimal permissions
# following the principle of least privilege.
# =============================================================================
provider "azuread" {}
