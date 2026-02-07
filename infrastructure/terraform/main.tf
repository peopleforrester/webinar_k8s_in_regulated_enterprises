# ==============================================================================
# MAIN TERRAFORM CONFIGURATION - FOUNDATIONAL RESOURCES
# ==============================================================================
#
# PURPOSE:
# This file establishes the foundational Azure resources required for the AKS
# deployment, including the resource group, monitoring infrastructure, and
# shared utilities used across other Terraform files.
#
# ARCHITECTURE OVERVIEW:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │                         Resource Group                                   │
# │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
# │  │     AKS     │  │     ACR     │  │  Key Vault  │  │  Log Analy- │    │
# │  │   Cluster   │  │  Registry   │  │   Secrets   │  │   tics WS   │    │
# │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
# │                                                                          │
# │  ┌─────────────────────────────────────────────────────────────────┐   │
# │  │                    Virtual Network                               │   │
# │  │  ┌───────────────────────┐  ┌───────────────────────┐          │   │
# │  │  │     AKS Subnet        │  │   Services Subnet     │          │   │
# │  │  └───────────────────────┘  └───────────────────────┘          │   │
# │  └─────────────────────────────────────────────────────────────────┘   │
# └─────────────────────────────────────────────────────────────────────────┘
#
# REGULATORY ALIGNMENT:
# - NCUA Part 748 Appendix A: Requires centralized logging and monitoring
# - OSFI B-13: Mandates audit trail retention (90+ days)
# - DORA Article 10: Requires detection capabilities for ICT-related incidents
#
# 2026 COMPLIANCE UPDATES:
# - Container Insights integration for Kubernetes 1.34 observability
# - Enhanced log categories for Cilium network policy auditing
# - Centralized monitoring supports Image Cleaner vulnerability reporting
# ==============================================================================

# =============================================================================
# DATA SOURCES
# =============================================================================
# Data sources retrieve information about existing Azure resources or
# the current execution context without creating or modifying anything.
# =============================================================================

# -----------------------------------------------------------------------------
# CURRENT CLIENT CONFIGURATION
# -----------------------------------------------------------------------------
# Retrieves information about the identity running Terraform:
# - tenant_id: The Entra ID (Azure AD) tenant
# - subscription_id: The target Azure subscription
# - object_id: The principal ID of the current user/service principal
# - client_id: The application ID (for service principals)
#
# WHY THIS MATTERS:
# - Key Vault access policies need the current user's object_id
# - Audit logs capture who deployed the infrastructure
# - Multi-tenant scenarios require tenant_id for cross-tenant access
#
# SECURITY NOTE:
# This data source exposes the identity of whoever runs 'terraform apply'.
# In regulated environments, ensure this is an authorized identity with
# appropriate change management approval.
# -----------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

# =============================================================================
# RESOURCE GROUP
# =============================================================================
# A resource group is a logical container for Azure resources. All resources
# in this deployment will be placed in a single resource group for:
# - Simplified lifecycle management (delete all resources at once)
# - Unified access control (RBAC applied at group level)
# - Cost tracking and billing organization
# - Regional consistency (all resources in same location)
#
# REGULATORY CONSIDERATIONS:
# - Resource groups support Azure Policy for compliance enforcement
# - Tags enable cost allocation and audit reporting
# - RBAC at this level controls who can manage the AKS cluster
#
# NAMING CONVENTION:
# "rg-" prefix follows Azure naming best practices for resource groups.
# Consistent naming aids in audit log analysis and resource discovery.
# =============================================================================
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# =============================================================================
# RANDOM STRING FOR GLOBALLY UNIQUE NAMES
# =============================================================================
# Many Azure resources require globally unique names across all Azure tenants.
# This includes:
# - Key Vault names (must be unique across Azure globally)
# - Container Registry names (must be unique and forms the login URL)
# - Storage Account names (used in public URLs)
#
# WHY RANDOM INSTEAD OF DETERMINISTIC:
# - Avoids collisions with other organizations' resources
# - Prevents name squatting issues
# - Allows for blue-green deployments with unique names
#
# IMPORTANT STATE CONSIDERATIONS:
# - The random value is stored in Terraform state
# - Losing state means you cannot manage these resources
# - For regulated environments, ensure state is backed up and encrypted
#
# LENGTH RATIONALE:
# 6 characters provides 2,176,782,336 possible combinations (36^6),
# offering a very low probability of collision while keeping names readable.
# =============================================================================
resource "random_string" "suffix" {
  length  = 6     # Short enough to keep resource names readable
  special = false # Azure resource names cannot contain special characters
  upper   = false # Lowercase only for DNS compatibility (ACR login server)
}

# =============================================================================
# LOG ANALYTICS WORKSPACE
# =============================================================================
# The Log Analytics workspace is the central repository for all monitoring
# data in this deployment. It receives logs and metrics from:
# - AKS control plane (API server, scheduler, controller manager)
# - AKS nodes (kubelet, container runtime)
# - Container Insights (pod metrics, container logs)
# - Microsoft Defender for Containers (security alerts)
# - Key Vault (access logs, diagnostic events)
# - Container Registry (pull events, authentication)
#
# REGULATORY REQUIREMENTS:
# ┌─────────────┬─────────────────────────────────────────────────────────────┐
# │ Regulation  │ Logging Requirement                                         │
# ├─────────────┼─────────────────────────────────────────────────────────────┤
# │ NCUA 748    │ Must log all access to member data systems                  │
# │ OSFI B-13   │ Audit trail retention for minimum 7 years (some categories) │
# │ DORA Art 10 │ Detection and logging of ICT-related incidents              │
# │ PCI DSS 10  │ Track all access to network resources and cardholder data   │
# └─────────────┴─────────────────────────────────────────────────────────────┘
#
# SKU SELECTION:
# "PerGB2018" is the pay-per-use model where you pay for data ingested.
# For regulated environments with high log volumes, consider:
# - Commitment tiers for cost savings (100GB/day, 200GB/day, etc.)
# - Dedicated clusters for data isolation requirements
#
# RETENTION CONFIGURATION:
# - Default: 90 days (configurable via var.log_retention_days)
# - NCUA typically requires minimum 90 days
# - OSFI may require longer retention for certain log categories
# - Consider Log Analytics data export to Storage for long-term retention
#
# 2026 FEATURE INTEGRATION:
# - Receives Cilium network policy logs via kube-audit category
# - Captures Image Cleaner (Eraser) vulnerability scan results
# - Supports Kubernetes 1.34 enhanced audit log format
# =============================================================================
resource "azurerm_log_analytics_workspace" "main" {
  # Naming: law-<cluster-name>-<random-suffix>
  # The random suffix ensures uniqueness if multiple environments exist
  name                = "law-${var.cluster_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # ---------------------------------------------------------------------------
  # SKU: Pricing tier for the workspace
  # ---------------------------------------------------------------------------
  # "PerGB2018" = Pay-as-you-go model
  # - You pay for data ingested (per GB)
  # - No upfront commitment required
  # - Good for variable or unknown workloads
  #
  # ALTERNATIVE SKUS:
  # - "CapacityReservation": Commit to daily ingestion volume for discounts
  # - "Free": Limited to 500MB/day, 7-day retention (not for production)
  # ---------------------------------------------------------------------------
  sku = "PerGB2018"

  # ---------------------------------------------------------------------------
  # RETENTION: How long to keep data in the workspace
  # ---------------------------------------------------------------------------
  # Configurable from 30 to 730 days (2 years)
  #
  # COST IMPLICATIONS:
  # - Retention up to 90 days is included in ingestion price
  # - Beyond 90 days incurs additional per-GB-per-month charges
  #
  # REGULATORY GUIDANCE:
  # - Start with 90 days for operational monitoring
  # - Use data export to Storage Account for long-term archival
  # - Storage Account provides cheaper long-term retention with
  #   configurable lifecycle policies (hot -> cool -> archive)
  # ---------------------------------------------------------------------------
  retention_in_days = var.log_retention_days

  # Tags for cost allocation and resource identification
  tags = var.tags
}

# =============================================================================
# CONTAINER INSIGHTS SOLUTION
# =============================================================================
# Container Insights is Azure's comprehensive container monitoring solution
# that provides deep visibility into AKS cluster health and performance.
#
# WHAT CONTAINER INSIGHTS PROVIDES:
# ┌────────────────────────────────────────────────────────────────────────────┐
# │ Capability              │ Description                                      │
# ├────────────────────────────────────────────────────────────────────────────┤
# │ Node Metrics            │ CPU, memory, disk usage per node                 │
# │ Pod Metrics             │ Resource consumption per pod/container           │
# │ Container Logs          │ stdout/stderr from all containers                │
# │ Kubernetes Events       │ Cluster events (scheduling, scaling, errors)     │
# │ Live Data               │ Real-time streaming of logs and metrics          │
# │ Prometheus Integration  │ Scrape custom metrics from workloads             │
# │ Recommended Alerts      │ Pre-built alert rules for common issues          │
# │ Workbooks               │ Interactive dashboards for investigation         │
# └────────────────────────────────────────────────────────────────────────────┘
#
# HOW IT WORKS:
# 1. The oms_agent in aks.tf deploys a DaemonSet to each node
# 2. The agent collects metrics and logs from the kubelet and containers
# 3. Data is sent to this Log Analytics workspace
# 4. Container Insights solution provides the visualization and analysis layer
#
# REGULATORY VALUE:
# - NCUA: Provides evidence of system monitoring and incident detection
# - OSFI B-13: Supports technology risk monitoring requirements
# - DORA Article 10: Enables incident detection and response capabilities
#
# 2026 KUBERNETES 1.34 INTEGRATION:
# - Enhanced metrics for Cilium network policy enforcement
# - Visibility into AzureLinux node performance characteristics
# - Integration with Image Cleaner scan results for vulnerability tracking
#
# COST OPTIMIZATION:
# Container Insights can generate significant log volume. Consider:
# - Configuring collection settings to exclude verbose logs
# - Using Basic logs tier for container logs (lower cost, limited query)
# - Setting up data collection rules to filter unnecessary data
# =============================================================================
resource "azurerm_log_analytics_solution" "containers" {
  # Solution name must be exactly "ContainerInsights" (Azure requirement)
  solution_name = "ContainerInsights"
  location      = azurerm_resource_group.main.location

  resource_group_name = azurerm_resource_group.main.name

  # Link to the Log Analytics workspace where data will be stored
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name

  # ---------------------------------------------------------------------------
  # SOLUTION PLAN
  # ---------------------------------------------------------------------------
  # The plan specifies the publisher and product for the solution.
  # This is a Microsoft first-party solution available through the
  # Operations Management Suite (OMS) gallery.
  #
  # NOTE: While the solution is free, you pay for data ingestion
  # into the Log Analytics workspace.
  # ---------------------------------------------------------------------------
  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }
}
