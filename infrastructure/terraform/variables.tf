# ==============================================================================
# TERRAFORM VARIABLES - INPUT CONFIGURATION
# ==============================================================================
#
# PURPOSE:
# This file defines all configurable parameters for the AKS deployment.
# Variables allow the same Terraform code to deploy different environments
# (dev, staging, production) with environment-specific settings.
#
# VARIABLE TYPES IN THIS FILE:
# - Infrastructure naming and location
# - Kubernetes version and node sizing
# - Security and monitoring configuration
# - Resource tagging for governance
#
# USAGE:
# Variables can be set via:
# 1. terraform.tfvars file (recommended for environments)
# 2. -var flag: terraform apply -var="cluster_name=aks-prod"
# 3. Environment variables: TF_VAR_cluster_name=aks-prod
# 4. Interactive prompt (if no default provided)
#
# REGULATORY ALIGNMENT:
# - NCUA Part 748: Variables enable consistent, auditable configurations
# - OSFI B-13: Parameterization supports change management processes
# - DORA Article 9: Configuration management for ICT assets
#
# BEST PRACTICES FOR REGULATED ENVIRONMENTS:
# - Use terraform.tfvars files per environment, stored in version control
# - Sensitive variables (not present here) should use environment variables
# - Document all non-default values in change management tickets
# ==============================================================================

# =============================================================================
# INFRASTRUCTURE NAMING AND LOCATION
# =============================================================================

# -----------------------------------------------------------------------------
# RESOURCE GROUP NAME
# -----------------------------------------------------------------------------
# The resource group is the top-level container for all Azure resources.
# All resources in this deployment will be created within this group.
#
# NAMING CONVENTION:
# "rg-" prefix is Azure's recommended prefix for resource groups.
# Including environment name (demo/dev/prod) helps with identification.
#
# REGULATORY CONSIDERATIONS:
# - Use consistent naming across environments for audit clarity
# - Include project or application name for cost allocation
# - Avoid PII or sensitive information in resource names (they're visible)
# -----------------------------------------------------------------------------
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-aks-regulated-demo"
}

# -----------------------------------------------------------------------------
# AZURE REGION (LOCATION)
# -----------------------------------------------------------------------------
# The Azure region where all resources will be deployed.
#
# REGION SELECTION CONSIDERATIONS FOR REGULATED ENTERPRISES:
#
# 1. DATA RESIDENCY:
#    - NCUA/US Credit Unions: Consider US regions only
#    - OSFI/Canadian Banks: Canada Central or Canada East
#    - DORA/EU Financial Institutions: EU regions for GDPR alignment
#
# 2. AVAILABILITY:
#    - Choose regions with Availability Zones for HA (most major regions)
#    - Consider paired regions for disaster recovery (eastus2 pairs with centralus)
#
# 3. COMPLIANCE CERTIFICATIONS:
#    - Not all regions have the same compliance certifications
#    - Verify region supports required certifications (SOC2, ISO27001, etc.)
#    - See: https://docs.microsoft.com/azure/compliance/
#
# 4. SERVICE AVAILABILITY:
#    - Kubernetes 1.34 and latest AKS features may roll out to regions gradually
#    - eastus2 typically receives features early
#
# DEFAULT RATIONALE:
# eastus2 offers:
# - Full AKS feature availability including 1.34
# - Availability Zone support
# - Competitive pricing
# - Comprehensive compliance certifications
# -----------------------------------------------------------------------------
variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus2"
}

# -----------------------------------------------------------------------------
# AKS CLUSTER NAME
# -----------------------------------------------------------------------------
# The name of the Azure Kubernetes Service cluster.
# This name is also used as a prefix for related resources (VNet, NSG, etc.).
#
# NAMING RULES:
# - Must be 1-63 characters
# - Alphanumeric characters and hyphens only
# - Must start with a letter and end with alphanumeric
# - Must be unique within the resource group
#
# NAMING CONVENTION RECOMMENDATION:
# aks-<workload>-<environment>
# Examples: aks-payments-prod, aks-core-banking-dev
# -----------------------------------------------------------------------------
variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-regulated-demo"
}

# =============================================================================
# KUBERNETES CONFIGURATION
# =============================================================================

# -----------------------------------------------------------------------------
# KUBERNETES VERSION
# -----------------------------------------------------------------------------
# The Kubernetes version to deploy on the AKS cluster.
#
# 2026 COMPLIANCE UPDATE - KUBERNETES 1.34:
# This configuration uses Kubernetes 1.34, which includes critical features
# for regulated enterprises:
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Feature                    │ Regulatory Benefit                          │
# ├──────────────────────────────────────────────────────────────────────────┤
# │ Sidecar Containers (GA)    │ Better security with service mesh patterns  │
# │ CRD Validation Ratcheting  │ Safer policy rollouts without breaking apps │
# │ AppArmor Support (GA)      │ Mandatory access control for containers     │
# │ Pod Scheduling Readiness   │ More reliable workload placement            │
# │ Contextual Logging         │ Enhanced audit trail for compliance         │
# └──────────────────────────────────────────────────────────────────────────┘
#
# VERSION STRATEGY:
# - AKS supports N-2 versions (current GA minus two minor versions)
# - Minor versions are supported for ~14 months
# - Plan upgrades quarterly to stay within support window
#
# UPGRADE PATH:
# Kubernetes follows semantic versioning. You can only upgrade one minor
# version at a time (1.33 -> 1.34, not 1.32 -> 1.34 directly).
#
# REGULATORY REQUIREMENTS:
# - NCUA: Maintain supported software versions
# - OSFI B-13: Technology currency and patch management
# - DORA Article 7: ICT systems kept up to date
# -----------------------------------------------------------------------------
variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.34"
}

# =============================================================================
# NODE POOL SIZING
# =============================================================================
# AKS uses node pools to group virtual machines with the same configuration.
# This deployment uses two node pools:
# 1. System pool: Runs Kubernetes system components (CoreDNS, metrics-server)
# 2. User pool: Runs application workloads
#
# SEPARATION RATIONALE:
# - Isolates system components from noisy neighbor effects
# - Allows different sizing for system vs. application needs
# - System pool uses "only_critical_addons_enabled" taint
# - Meets CIS Kubernetes Benchmark recommendations for node separation
# =============================================================================

# -----------------------------------------------------------------------------
# SYSTEM NODE POOL CONFIGURATION
# -----------------------------------------------------------------------------
variable "system_node_count" {
  description = "Number of system nodes"
  type        = number
  default     = 3 # Minimum 3 for high availability across Availability Zones

  # VALIDATION: System pool should have at least 2 nodes for HA
  # Uncomment for production:
  # validation {
  #   condition     = var.system_node_count >= 2
  #   error_message = "System node pool must have at least 2 nodes for high availability."
  # }
}

# -----------------------------------------------------------------------------
# SYSTEM NODE VM SIZE
# -----------------------------------------------------------------------------
# The Azure VM SKU for system nodes.
#
# SYSTEM POOL SIZING CONSIDERATIONS:
# - Runs: CoreDNS, kube-proxy, metrics-server, CSI drivers
# - Additional add-ons: Azure Policy, Defender, OMS agent, Key Vault CSI
# - Minimum recommended: 2 vCPUs, 8 GB RAM
#
# DEFAULT: Standard_D4s_v3
# - 4 vCPUs, 16 GB RAM
# - Premium SSD support (required for production)
# - Provides headroom for add-ons and monitoring agents
#
# COST-SAVING ALTERNATIVES FOR NON-PRODUCTION:
# - Standard_D2s_v3: 2 vCPUs, 8 GB RAM (minimum viable)
# - Standard_B4ms: Burstable, cheaper for intermittent workloads
# -----------------------------------------------------------------------------
variable "system_node_vm_size" {
  description = "VM size for system nodes"
  type        = string
  default     = "Standard_D2s_v3"  # 2 vCPU - reduced for demo (10 vCPU quota)
}

# -----------------------------------------------------------------------------
# USER NODE POOL CONFIGURATION
# -----------------------------------------------------------------------------
variable "user_node_count" {
  description = "Number of user workload nodes"
  type        = number
  default     = 0 # Disabled for demo - system pool handles workloads

  # VALIDATION: Ensure reasonable starting count
  # validation {
  #   condition     = var.user_node_count >= 2 && var.user_node_count <= 100
  #   error_message = "User node count must be between 2 and 100."
  # }
}

# -----------------------------------------------------------------------------
# USER NODE VM SIZE
# -----------------------------------------------------------------------------
# The Azure VM SKU for application workload nodes.
#
# SIZING STRATEGY:
# Size nodes based on your largest pod resource request, not average usage.
# Kubernetes schedules based on requests, not actual usage.
#
# FORMULA:
# Max pods per node = (Node allocatable memory - buffer) / Largest pod request
#
# EXAMPLE CALCULATION:
# Standard_D4s_v3: 16 GB RAM, ~14.5 GB allocatable
# Largest pod: 2 GB request
# Max pods: ~7 per node (with overhead buffer)
#
# REGULATED WORKLOAD CONSIDERATIONS:
# - Memory-intensive: Fraud detection, ML models
# - CPU-intensive: Transaction processing, encryption
# - Balanced: Standard microservices
# -----------------------------------------------------------------------------
variable "user_node_vm_size" {
  description = "VM size for user workload nodes"
  type        = string
  default     = "Standard_D2s_v3"  # 2 vCPU - reduced for demo (10 vCPU quota)
}

# =============================================================================
# RESOURCE TAGGING
# =============================================================================
# Tags are key-value pairs attached to Azure resources for:
# - Cost allocation and billing reports
# - Resource organization and discovery
# - Automation and policy enforcement
# - Audit and compliance reporting
#
# REGULATORY REQUIREMENTS:
# - NCUA: Asset inventory and classification
# - OSFI B-13: IT asset management
# - DORA Article 5: ICT risk management framework
#
# RECOMMENDED TAGS FOR REGULATED ENVIRONMENTS:
# - Environment: Production, Staging, Development
# - CostCenter: For chargeback and allocation
# - DataClassification: Public, Internal, Confidential, Restricted
# - Compliance: Applicable regulations (NCUA, OSFI, DORA)
# - Owner: Team or individual responsible
# - Application: Application or service name
# =============================================================================
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Demo"
    Project     = "AKS-Regulated-Enterprise"
    ManagedBy   = "Terraform"
  }
}

# =============================================================================
# SECURITY AND MONITORING CONFIGURATION
# =============================================================================

# -----------------------------------------------------------------------------
# MICROSOFT DEFENDER FOR CONTAINERS
# -----------------------------------------------------------------------------
# Defender for Containers provides comprehensive container security:
#
# CAPABILITIES:
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Feature                  │ Description                                   │
# ├──────────────────────────────────────────────────────────────────────────┤
# │ Vulnerability Scanning   │ Scans images in ACR and running containers    │
# │ Runtime Protection       │ Detects anomalous container behavior          │
# │ Kubernetes Hardening     │ Recommendations based on CIS benchmarks       │
# │ Admission Control        │ Block deployment of vulnerable images         │
# │ Network Segmentation     │ Visualize and alert on pod communications     │
# │ Threat Detection         │ ML-based detection of attacks and exploits    │
# └──────────────────────────────────────────────────────────────────────────┘
#
# REGULATORY ALIGNMENT:
# - NCUA Part 748: Requires threat detection and response capabilities
# - OSFI B-13: Mandates security monitoring and vulnerability management
# - DORA Article 6: ICT security and vulnerability assessment
#
# COST CONSIDERATION:
# Defender is priced per cluster core. For a 12-core cluster (3x D4s_v3),
# expect approximately $7/core/month = ~$84/month.
#
# ALTERNATIVE FOR COST-SENSITIVE ENVIRONMENTS:
# Set to false and use:
# - Image Cleaner (included) for basic vulnerability scanning
# - Open-source tools like Falco for runtime detection
# - Manual scanning with Trivy or Grype
# -----------------------------------------------------------------------------
variable "enable_defender" {
  description = "Enable Microsoft Defender for Containers"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# LOG RETENTION PERIOD
# -----------------------------------------------------------------------------
# How many days to retain logs in Log Analytics workspace.
#
# RETENTION TIERS:
# - 30-90 days: Included in Log Analytics pricing
# - 91-730 days: Additional per-GB storage charges apply
#
# REGULATORY MINIMUM REQUIREMENTS:
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Regulation   │ Typical Requirement                                       │
# ├──────────────────────────────────────────────────────────────────────────┤
# │ NCUA         │ 90 days operational + longer for audit trails             │
# │ OSFI B-13    │ Varies by log type; some require 7 years                  │
# │ DORA         │ Must retain logs sufficient for incident analysis         │
# │ PCI DSS      │ 1 year, with 3 months immediately available               │
# │ SOC 2        │ Typically 1 year for audit evidence                       │
# └──────────────────────────────────────────────────────────────────────────┘
#
# LONG-TERM ARCHIVAL STRATEGY:
# For retention beyond 730 days (2 years):
# 1. Configure Log Analytics data export to Storage Account
# 2. Use Storage Account lifecycle management (hot -> cool -> archive)
# 3. Archive tier provides very low cost for long-term compliance storage
#
# DEFAULT RATIONALE:
# 90 days provides a good balance of:
# - Sufficient data for incident investigation
# - No additional retention charges
# - Alignment with common regulatory minimums
# -----------------------------------------------------------------------------
variable "log_retention_days" {
  description = "Log Analytics retention in days"
  type        = number
  default     = 90

  # VALIDATION: Ensure retention is within Azure limits
  # validation {
  #   condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
  #   error_message = "Log retention must be between 30 and 730 days."
  # }
}

# =============================================================================
# API SERVER ACCESS CONTROL
# =============================================================================

# -----------------------------------------------------------------------------
# KARPENTER NODE AUTOPROVISIONING
# -----------------------------------------------------------------------------
# Controls whether Karpenter (AKS Node Autoprovisioning) should be enabled.
#
# NOTE: azurerm ~> 3.85 does not support node_provisioning_profile. The
# install-tools.sh tier4 script enables Karpenter via Azure CLI:
#   az aks update -g <rg> -n <cluster> --node-provisioning-mode Auto
# When upgrading to azurerm >= 4.57, add a node_provisioning_profile block
# to aks.tf and reference this variable directly.
#
# WHAT CHANGES WHEN ENABLED:
# - AKS deploys the Karpenter controller to kube-system namespace
# - Cluster-autoscaler is disabled for Karpenter-managed node pools
# - NodePool and AKSNodeClass CRDs become available
#
# PREREQUISITES:
# - AKS cluster must be running Kubernetes >= 1.29
# - Requires OIDC issuer enabled (already set in this config)
#
# REGULATORY CONTEXT:
# Karpenter provides better capacity management (DORA Art.11) by selecting
# optimal VM sizes per workload, reducing waste and improving bin-packing.
# -----------------------------------------------------------------------------
variable "enable_karpenter" {
  description = "Enable AKS Node Autoprovisioning (Karpenter) - used by install-tools.sh tier4"
  type        = bool
  default     = true
}

# =============================================================================
# API SERVER ACCESS CONTROL
# =============================================================================

variable "api_server_authorized_ip_ranges" {
  description = "List of IP ranges (CIDR) allowed to access the AKS API server. Leave empty for unrestricted access."
  type        = list(string)
  default     = []  # Empty = unrestricted (add your IP/32 for restricted access)
  # Example: ["71.131.87.246/32", "10.0.0.0/8"]
}
