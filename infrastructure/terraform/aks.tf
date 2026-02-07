# ==============================================================================
# AZURE KUBERNETES SERVICE (AKS) CLUSTER CONFIGURATION
# ==============================================================================
#
# PURPOSE:
# This file defines the AKS cluster and its node pools, configured for
# regulated enterprise environments such as financial institutions subject
# to NCUA, OSFI, and DORA compliance requirements.
#
# 2026 COMPLIANCE UPDATES IMPLEMENTED:
# This configuration incorporates the latest AKS features for regulated
# environments, addressing the Azure NPM deprecation and new security tooling:
#
# ┌──────────────────────────────────────────────────────────────────────────────┐
# │ Feature              │ Status  │ Why It Matters for Regulated Enterprises   │
# ├──────────────────────────────────────────────────────────────────────────────┤
# │ Kubernetes 1.34      │ GA      │ Latest security patches, AppArmor GA       │
# │ Cilium CNI           │ GA      │ Replaces NPM (retiring Sep 2026/2028)      │
# │ Azure CNI Overlay    │ GA      │ Efficient IP management for large clusters │
# │ AzureLinux           │ GA      │ Hardened OS, faster patches, FIPS support  │
# │ Image Cleaner        │ GA      │ Automated CVE removal (Eraser-based)       │
# │ Workload Identity    │ GA      │ Pod-level identity without secrets         │
# │ Key Vault CSI        │ GA      │ Secrets mounted as files, auto-rotation    │
# │ Microsoft Defender   │ GA      │ Runtime threat detection and response      │
# └──────────────────────────────────────────────────────────────────────────────┘
#
# ARCHITECTURE:
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           AKS Cluster                                        │
# │                                                                              │
# │  ┌─────────────────────────┐  ┌─────────────────────────────────────────┐  │
# │  │     System Node Pool     │  │           User Node Pool                 │  │
# │  │  (3 nodes, AzureLinux)   │  │  (3-10 nodes, auto-scaling, AzureLinux) │  │
# │  │                          │  │                                          │  │
# │  │  - CoreDNS              │  │  - Application workloads                 │  │
# │  │  - kube-proxy           │  │  - Scheduled based on labels             │  │
# │  │  - Cilium agent         │  │  - Auto-scales based on demand           │  │
# │  │  - CSI drivers          │  │                                          │  │
# │  │  - OMS agent            │  │                                          │  │
# │  │  - Defender agent       │  │                                          │  │
# │  └─────────────────────────┘  └─────────────────────────────────────────┘  │
# │                                                                              │
# │  Security Features:                                                          │
# │  - Entra ID (Azure AD) RBAC                                                 │
# │  - Workload Identity (OIDC)                                                 │
# │  - Key Vault CSI Driver                                                     │
# │  - Azure Policy                                                             │
# │  - Microsoft Defender                                                       │
# │  - Image Cleaner (Eraser)                                                   │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# REGULATORY ALIGNMENT:
# - NCUA Part 748: Access controls, audit trails, encryption
# - OSFI B-13: Technology risk management, patch management
# - DORA Article 5-11: ICT risk management, security, incident handling
# - CIS Kubernetes Benchmark: Security hardening best practices
# ==============================================================================

# =============================================================================
# USER-ASSIGNED MANAGED IDENTITY
# =============================================================================
# A managed identity provides an identity for the AKS cluster to authenticate
# to other Azure services without storing credentials in code or configuration.
#
# WHY USER-ASSIGNED (vs SYSTEM-ASSIGNED):
# - Lifecycle independent of the cluster (survives cluster recreation)
# - Can be pre-created and assigned permissions before cluster creation
# - Can be shared across multiple resources if needed
# - Better for Infrastructure-as-Code workflows
#
# WHAT THIS IDENTITY IS USED FOR:
# - Managing Azure Load Balancers for Kubernetes services
# - Creating/attaching managed disks for persistent volumes
# - Updating DNS records for ingress controllers
# - Network operations (when AKS manages the VNet)
#
# NOTE: The kubelet identity (for ACR pull) is separate and system-assigned.
#
# REGULATORY ALIGNMENT:
# - NCUA: Non-repudiation through identity-based access
# - OSFI B-13: Identity and access management
# - DORA Article 9: Access control policies
# =============================================================================
resource "azurerm_user_assigned_identity" "aks" {
  # Naming: id-<cluster-name>
  # "id-" prefix indicates this is an identity resource
  name                = "id-${var.cluster_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# =============================================================================
# NETWORK CONTRIBUTOR ROLE ASSIGNMENT
# =============================================================================
# Grants the AKS identity permission to manage network resources in the VNet.
#
# WHY THIS IS NEEDED:
# When AKS creates LoadBalancer services, it needs to:
# - Create/update public or private load balancers
# - Manage load balancer rules and backend pools
# - Create/update network security group rules
# - Attach network interfaces to subnets
#
# SCOPE: Virtual Network
# Scoped to the VNet (not the entire resource group or subscription) following
# the principle of least privilege.
#
# PERMISSION INCLUDED IN "Network Contributor":
# - Microsoft.Network/virtualNetworks/*
# - Microsoft.Network/loadBalancers/*
# - Microsoft.Network/networkSecurityGroups/*
# - Microsoft.Network/publicIPAddresses/*
# - And other network-related permissions
#
# SECURITY NOTE:
# This role does NOT include:
# - Ability to create VNets or subnets (already exist)
# - Data plane access to VMs or containers
# - Access to other resource types
# =============================================================================
resource "azurerm_role_assignment" "aks_network" {
  # Scope limited to the VNet, not broader resource group
  scope                = azurerm_virtual_network.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# =============================================================================
# AKS CLUSTER RESOURCE
# =============================================================================
# This is the primary AKS cluster resource. It defines the control plane
# configuration, default node pool, and enabled features.
#
# CONTROL PLANE:
# AKS is a managed Kubernetes service where Microsoft manages:
# - API server (etcd, kube-apiserver)
# - Controller manager and scheduler
# - Core add-ons (CoreDNS, kube-proxy)
# - Upgrades and patching of control plane
#
# YOU MANAGE:
# - Node pools (this configuration)
# - Workload deployments
# - Network policies
# - Application security
# =============================================================================
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # ---------------------------------------------------------------------------
  # DNS PREFIX
  # ---------------------------------------------------------------------------
  # Creates the FQDN for the Kubernetes API server:
  # <dns_prefix>.<location>.azmk8s.io
  #
  # Example: aks-regulated-demo.eastus2.azmk8s.io
  #
  # This is used for kubectl access and must be unique within the region.
  # ---------------------------------------------------------------------------
  dns_prefix = var.cluster_name

  # ---------------------------------------------------------------------------
  # KUBERNETES VERSION
  # ---------------------------------------------------------------------------
  # Specifies the Kubernetes version for the control plane and default node pool.
  #
  # 2026 UPDATE - KUBERNETES 1.34:
  # Key features in 1.34 for regulated enterprises:
  # - Sidecar Containers (GA): Better service mesh patterns for mTLS
  # - AppArmor (GA): Mandatory access control for containers
  # - Pod Scheduling Readiness: More reliable workload placement
  # - CRD Validation Ratcheting: Safer policy rollouts
  #
  # VERSION SUPPORT:
  # - AKS supports N-2 (current GA minus two minor versions)
  # - Each minor version supported for ~14 months
  # - Plan quarterly upgrade reviews to stay supported
  #
  # UPGRADE STRATEGY:
  # Use automatic_channel_upgrade (below) for automated upgrades.
  # ---------------------------------------------------------------------------
  kubernetes_version = var.kubernetes_version

  tags = var.tags

  # ---------------------------------------------------------------------------
  # CLUSTER IDENTITY
  # ---------------------------------------------------------------------------
  # Configures how the AKS cluster authenticates to Azure services.
  #
  # USER-ASSIGNED MANAGED IDENTITY:
  # - The identity we created above
  # - Used for Azure resource management (load balancers, disks, etc.)
  # - Survives cluster recreation
  #
  # ALTERNATIVES NOT USED:
  # - SystemAssigned: Auto-created, deleted with cluster
  # - Service Principal: Legacy, requires secret rotation
  # ---------------------------------------------------------------------------
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  # ===========================================================================
  # SYSTEM NODE POOL (DEFAULT)
  # ===========================================================================
  # The default node pool runs Kubernetes system components and add-ons.
  # Separating system and user workloads is a best practice that:
  # - Prevents user workloads from impacting system components
  # - Allows different sizing for system vs. application needs
  # - Aligns with CIS Kubernetes Benchmark recommendations
  #
  # WHAT RUNS ON SYSTEM NODES:
  # - CoreDNS: Cluster DNS resolution
  # - kube-proxy: Network proxying (though Cilium may replace this)
  # - Cilium agents: eBPF-based networking
  # - Azure CSI drivers: Storage integration
  # - OMS agent: Monitoring and logging
  # - Defender agent: Security scanning
  # - Key Vault CSI driver: Secrets management
  # - Azure Policy agent: Compliance enforcement
  # ===========================================================================
  default_node_pool {
    name       = "system"
    node_count = var.system_node_count
    vm_size    = var.system_node_vm_size

    # -------------------------------------------------------------------------
    # NETWORK CONFIGURATION
    # -------------------------------------------------------------------------
    # Nodes are deployed into the AKS subnet defined in networking.tf.
    # With Azure CNI Overlay, only nodes consume IPs from this subnet.
    # -------------------------------------------------------------------------
    vnet_subnet_id = azurerm_subnet.aks.id

    # -------------------------------------------------------------------------
    # STORAGE CONFIGURATION
    # -------------------------------------------------------------------------
    # os_disk_size_gb: 128 GB provides ample space for:
    # - Container images (local cache)
    # - Ephemeral storage for pods
    # - System logs and temporary files
    #
    # os_disk_type: "Managed" uses Azure Managed Disks which provide:
    # - 99.9% SLA for single instance VMs
    # - Automatic replication within the datacenter
    # - Support for disk snapshots
    #
    # PERFORMANCE CONSIDERATION:
    # For performance-critical workloads, consider:
    # - "Ephemeral" OS disks: Uses VM cache, no network latency
    # - Premium SSD: Better IOPS and throughput
    # -------------------------------------------------------------------------
    os_disk_size_gb = 128
    os_disk_type    = "Managed"

    # -------------------------------------------------------------------------
    # OPERATING SYSTEM - AZURELINUX (2026 COMPLIANCE UPDATE)
    # -------------------------------------------------------------------------
    # AzureLinux (formerly CBL-Mariner) is Microsoft's internal Linux
    # distribution, now recommended for AKS workloads.
    #
    # WHY AZURELINUX FOR REGULATED ENTERPRISES:
    #
    # 1. SECURITY:
    #    - Minimal attack surface (only essential packages)
    #    - Hardened by default following CIS benchmarks
    #    - FIPS 140-2 validated cryptography available
    #    - SELinux enabled by default
    #
    # 2. FASTER PATCHING:
    #    - Microsoft-owned, faster CVE response
    #    - Patches don't depend on upstream distro timelines
    #    - Security updates within 24-48 hours for critical CVEs
    #
    # 3. PERFORMANCE:
    #    - Optimized for container workloads
    #    - Smaller base image (faster node startup)
    #    - Lower resource overhead
    #
    # 4. SUPPORT:
    #    - Fully supported by Microsoft
    #    - Integrated with AKS roadmap
    #    - Long-term support (LTS) versions available
    #
    # REGULATORY ALIGNMENT:
    # - NCUA: Hardened systems, timely patching
    # - OSFI B-13: Technology risk management, patch currency
    # - DORA Article 7: ICT systems security updates
    # -------------------------------------------------------------------------
    os_sku = "AzureLinux"

    # -------------------------------------------------------------------------
    # NODE POOL TYPE
    # -------------------------------------------------------------------------
    # VirtualMachineScaleSets (VMSS) is required for:
    # - Cluster autoscaler functionality
    # - Multiple node pools
    # - Availability Zone support
    # - Spot instances (for cost savings on non-critical workloads)
    #
    # AvailabilitySets is legacy and no longer recommended.
    # -------------------------------------------------------------------------
    type = "VirtualMachineScaleSets"

    # -------------------------------------------------------------------------
    # AUTO-SCALING
    # -------------------------------------------------------------------------
    # Disabled for system pool because:
    # - System workloads have predictable resource needs
    # - Scaling system nodes can impact cluster stability
    # - 3 nodes provides HA across Availability Zones
    #
    # If you need auto-scaling on system pool, ensure min_count >= 2.
    # -------------------------------------------------------------------------
    enable_auto_scaling = false

    # -------------------------------------------------------------------------
    # NODE LABELS
    # -------------------------------------------------------------------------
    # Labels are key-value pairs attached to nodes that can be used for:
    # - Pod scheduling (nodeSelector, nodeAffinity)
    # - Identifying node pool purpose
    # - Reporting and monitoring
    #
    # BEST PRACTICE:
    # Use consistent labeling scheme across all clusters:
    # - nodepool-type: system | user | gpu | memory-optimized
    # - environment: production | staging | development
    # - compliance: pci | hipaa | gdpr (if applicable)
    # -------------------------------------------------------------------------
    node_labels = {
      "nodepool-type" = "system"
      "environment"   = "demo"
    }

    # -------------------------------------------------------------------------
    # SYSTEM POOL TAINT
    # -------------------------------------------------------------------------
    # only_critical_addons_enabled = true applies the taint:
    # CriticalAddonsOnly=true:NoSchedule
    #
    # This ensures only system pods (with matching tolerations) are scheduled
    # on system nodes, keeping user workloads on user node pools.
    #
    # PODS THAT TOLERATE THIS TAINT:
    # - CoreDNS
    # - kube-proxy
    # - Azure CSI drivers
    # - Monitoring agents (OMS, Defender)
    # - Network policy controllers (Cilium)
    #
    # USER WORKLOADS:
    # Will be scheduled on the user node pool (defined below).
    # -------------------------------------------------------------------------
    only_critical_addons_enabled = true

    tags = var.tags
  }

  # ===========================================================================
  # NETWORK PROFILE - AZURE CNI WITH CILIUM (2026 COMPLIANCE UPDATE)
  # ===========================================================================
  # This network configuration implements Azure's recommended stack for 2026:
  # - Azure CNI: Native Azure networking integration
  # - Overlay mode: Efficient IP address management
  # - Cilium: eBPF-based network policies and observability
  #
  # WHY THIS COMBINATION:
  #
  # 1. AZURE NPM DEPRECATION:
  #    Azure Network Policy Manager (NPM) is being retired:
  #    - Windows: September 2026
  #    - Linux: September 2028
  #    Cilium is Microsoft's recommended replacement.
  #
  # 2. CILIUM ADVANTAGES:
  #    - eBPF-based: Faster, more efficient than iptables
  #    - L7 policies: Filter by HTTP path, method, headers
  #    - No 250-node limit: NPM had scaling issues at 250 nodes
  #    - Hubble: Built-in network observability
  #    - Service mesh: Optional Cilium mesh integration
  #
  # 3. OVERLAY MODE BENEFITS:
  #    - Pods use overlay network (192.168.0.0/16)
  #    - Only nodes consume VNet IPs
  #    - Supports up to 250,000 pods per cluster
  #    - Simplifies IP planning
  #
  # REGULATORY ALIGNMENT:
  # - NCUA: Network segmentation for data protection
  # - OSFI B-13: Network security controls
  # - DORA Article 6: Network security and segmentation
  # ===========================================================================
  network_profile {
    # -------------------------------------------------------------------------
    # NETWORK PLUGIN: azure
    # -------------------------------------------------------------------------
    # Azure CNI provides:
    # - Pods get routable IPs (or overlay IPs with overlay mode)
    # - Native Azure networking integration
    # - Support for Windows containers
    # - VNet integration for pod-to-Azure-service communication
    #
    # ALTERNATIVE: kubenet
    # - Basic routing with user-defined routes
    # - Less Azure integration
    # - Not recommended for regulated environments
    # -------------------------------------------------------------------------
    network_plugin = "azure"

    # -------------------------------------------------------------------------
    # NETWORK PLUGIN MODE: overlay
    # -------------------------------------------------------------------------
    # Overlay mode is a 2024+ feature that:
    # - Assigns pod IPs from a separate overlay CIDR (192.168.0.0/16)
    # - Reduces VNet IP consumption dramatically
    # - Required for Cilium network data plane
    #
    # IP CONSUMPTION COMPARISON:
    # Traditional Azure CNI: Nodes + (Pods per node * Node count)
    # Overlay Azure CNI: Just node count
    #
    # Example (100 nodes, 30 pods each):
    # - Traditional: 100 + (30 * 100) = 3,100 VNet IPs
    # - Overlay: 100 VNet IPs (pods use overlay)
    # -------------------------------------------------------------------------
    network_plugin_mode = "overlay"

    # -------------------------------------------------------------------------
    # NETWORK DATA PLANE: cilium (2026 COMPLIANCE UPDATE)
    # -------------------------------------------------------------------------
    # Cilium is an eBPF-based networking, security, and observability solution.
    #
    # KEY CAPABILITIES:
    #
    # 1. NETWORK POLICIES:
    #    - Kubernetes NetworkPolicy support
    #    - Cilium NetworkPolicy (extended features)
    #    - L7 filtering (HTTP, gRPC, Kafka)
    #    - DNS-aware policies
    #
    # 2. eBPF BENEFITS:
    #    - Kernel-level packet processing
    #    - No iptables chains (faster, more scalable)
    #    - Lower latency and CPU usage
    #    - Better performance at scale
    #
    # 3. OBSERVABILITY (Hubble):
    #    - Network flow visibility
    #    - Service dependency maps
    #    - Policy enforcement monitoring
    #    - Integrates with Prometheus/Grafana
    #
    # 4. REGULATORY BENEFITS:
    #    - Audit trail of network policy enforcement
    #    - Micro-segmentation for compliance
    #    - Encryption in transit with WireGuard (optional)
    #
    # MIGRATION FROM NPM:
    # If migrating from NPM:
    # 1. Export existing NetworkPolicies
    # 2. Test policies in non-production with Cilium
    # 3. Cilium is backward-compatible with K8s NetworkPolicy spec
    # -------------------------------------------------------------------------
    network_data_plane = "cilium"

    # -------------------------------------------------------------------------
    # LOAD BALANCER SKU
    # -------------------------------------------------------------------------
    # "standard" is required for:
    # - Availability Zone support
    # - Multiple frontend IPs
    # - Backend pool with up to 1000 instances
    # - Outbound rules for SNAT
    # - Network security group integration
    #
    # "basic" is legacy and being deprecated.
    # -------------------------------------------------------------------------
    load_balancer_sku = "standard"

    # -------------------------------------------------------------------------
    # OUTBOUND TYPE
    # -------------------------------------------------------------------------
    # Determines how pods access the internet for outbound connections.
    #
    # "loadBalancer": Uses Standard Load Balancer for outbound NAT
    # - Simplest configuration
    # - Pods share public IP(s) for outbound traffic
    # - Good for most scenarios
    #
    # ALTERNATIVES FOR REGULATED ENVIRONMENTS:
    # - "userDefinedRouting": Route through Azure Firewall
    #   - Full egress control and logging
    #   - Required for some compliance scenarios
    #   - Requires additional infrastructure
    #
    # - "managedNATGateway": Use NAT Gateway
    #   - Dedicated outbound IPs
    #   - Higher SNAT port availability
    #   - Better for high-connection workloads
    # -------------------------------------------------------------------------
    outbound_type = "loadBalancer"

    # -------------------------------------------------------------------------
    # SERVICE CIDR
    # -------------------------------------------------------------------------
    # The IP range for Kubernetes ClusterIP services.
    # These IPs are virtual and exist only within the cluster.
    #
    # 10.1.0.0/16 provides 65,536 service IPs.
    # Most clusters need far fewer (hundreds to low thousands).
    #
    # MUST NOT OVERLAP WITH:
    # - VNet address space (10.0.0.0/16)
    # - Pod CIDR (192.168.0.0/16)
    # - Any on-premises networks you route to
    # -------------------------------------------------------------------------
    service_cidr = "10.1.0.0/16"

    # -------------------------------------------------------------------------
    # DNS SERVICE IP
    # -------------------------------------------------------------------------
    # The IP address for the CoreDNS service.
    # Must be within the service_cidr range.
    # Typically .10 of the service CIDR by convention.
    #
    # All pods use this IP for DNS resolution by default.
    # -------------------------------------------------------------------------
    dns_service_ip = "10.1.0.10"

    # -------------------------------------------------------------------------
    # POD CIDR (Overlay)
    # -------------------------------------------------------------------------
    # The IP range for pod IPs in overlay mode.
    # These IPs are not routable outside the cluster.
    #
    # 192.168.0.0/16 provides 65,536 pod IPs.
    # Each node gets a /24 (254 pods) from this range.
    #
    # MUST NOT OVERLAP WITH:
    # - VNet address space (10.0.0.0/16)
    # - Service CIDR (10.1.0.0/16)
    # - On-premises networks (192.168.x.x is commonly used on-prem)
    #
    # ADJUSTMENT:
    # If 192.168.0.0/16 conflicts with your on-premises network,
    # use an alternative private range like 172.16.0.0/16.
    # -------------------------------------------------------------------------
    pod_cidr = "192.168.0.0/16"
  }

  # ===========================================================================
  # ENTRA ID (AZURE AD) INTEGRATION
  # ===========================================================================
  # Enables Azure Active Directory (now Entra ID) authentication and
  # authorization for the Kubernetes API server.
  #
  # WHY THIS MATTERS FOR REGULATED ENTERPRISES:
  # - Single identity source for all Azure and Kubernetes access
  # - Conditional access policies (require MFA, compliant devices)
  # - Just-in-time access with Privileged Identity Management (PIM)
  # - Audit trail in Entra ID sign-in logs
  # - Integration with enterprise identity governance
  #
  # REGULATORY ALIGNMENT:
  # - NCUA: Strong authentication requirements
  # - OSFI B-13: Identity and access management
  # - DORA Article 9: Access control and authentication
  # ===========================================================================
  azure_active_directory_role_based_access_control {
    # -------------------------------------------------------------------------
    # MANAGED MODE
    # -------------------------------------------------------------------------
    # "managed = true" uses AKS-managed Entra ID integration:
    # - AKS creates and manages the server application
    # - No need to create/manage Azure AD applications yourself
    # - Simpler setup and maintenance
    #
    # NOTE: This parameter is deprecated in azurerm v3.x and becomes the
    # default in v4.0. It will be removed in a future version.
    # See: https://aka.ms/aks/aad-legacy
    # -------------------------------------------------------------------------
    managed = true

    # -------------------------------------------------------------------------
    # AZURE RBAC FOR KUBERNETES
    # -------------------------------------------------------------------------
    # "azure_rbac_enabled = true" allows using Azure role assignments
    # to control Kubernetes access:
    #
    # BUILT-IN ROLES:
    # - Azure Kubernetes Service Cluster Admin Role: Full admin access
    # - Azure Kubernetes Service Cluster User Role: Read-only access
    # - Azure Kubernetes Service RBAC Admin: Manage RBAC within cluster
    # - Azure Kubernetes Service RBAC Cluster Admin: Full cluster admin
    # - Azure Kubernetes Service RBAC Reader: Read-only access
    # - Azure Kubernetes Service RBAC Writer: Read/write workloads
    #
    # BENEFITS:
    # - Unified RBAC across Azure and Kubernetes
    # - Leverage Entra ID groups for access management
    # - Audit in Azure Activity Logs
    # - Conditional Access integration
    # -------------------------------------------------------------------------
    azure_rbac_enabled = true
  }

  # ===========================================================================
  # WORKLOAD IDENTITY (OIDC)
  # ===========================================================================
  # Workload Identity enables pods to authenticate to Azure services using
  # Kubernetes service accounts, without storing secrets.
  #
  # HOW IT WORKS:
  # 1. AKS exposes an OIDC issuer endpoint
  # 2. Azure AD trusts this issuer via federated credentials
  # 3. Pods exchange their K8s service account token for Azure AD tokens
  # 4. The Azure AD token is used to access Azure services (Key Vault, etc.)
  #
  # WHY THIS IS CRITICAL FOR SECURITY:
  # - No secrets stored in cluster or configuration
  # - Tokens are short-lived and automatically rotated
  # - Pod-level identity (not node-level)
  # - Audit trail of which pod accessed what
  #
  # REGULATORY ALIGNMENT:
  # - NCUA: Eliminates stored credentials
  # - OSFI B-13: Strong authentication without secrets
  # - DORA: Secure authentication mechanisms
  # ===========================================================================
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ===========================================================================
  # MONITORING - CONTAINER INSIGHTS
  # ===========================================================================
  # The OMS agent deploys a DaemonSet that collects:
  # - Node metrics (CPU, memory, disk, network)
  # - Pod metrics (resource usage, restart counts)
  # - Container logs (stdout/stderr)
  # - Kubernetes events
  #
  # Data is sent to the Log Analytics workspace defined in main.tf.
  #
  # REGULATORY REQUIREMENTS:
  # - NCUA Part 748: System monitoring and logging
  # - OSFI B-13: Technology risk monitoring
  # - DORA Article 10: ICT incident detection
  # ===========================================================================
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # ===========================================================================
  # MICROSOFT DEFENDER FOR CONTAINERS
  # ===========================================================================
  # Conditional deployment based on var.enable_defender.
  # Defender provides comprehensive container security:
  #
  # CAPABILITIES:
  # - Vulnerability scanning: Images in ACR and running containers
  # - Runtime protection: Anomalous behavior detection
  # - Kubernetes hardening: CIS benchmark recommendations
  # - Admission control: Block vulnerable image deployment
  # - Threat detection: ML-based attack detection
  #
  # REGULATORY ALIGNMENT:
  # - NCUA: Threat detection and vulnerability management
  # - OSFI B-13: Security monitoring and vulnerability scanning
  # - DORA Article 6: ICT security and vulnerability assessment
  # ===========================================================================
  dynamic "microsoft_defender" {
    for_each = var.enable_defender ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
    }
  }

  # ===========================================================================
  # KEY VAULT SECRETS PROVIDER (CSI DRIVER)
  # ===========================================================================
  # Enables the Azure Key Vault Provider for Secrets Store CSI Driver.
  # This allows pods to mount Key Vault secrets as files or environment variables.
  #
  # HOW IT WORKS:
  # 1. Create a SecretProviderClass resource referencing Key Vault secrets
  # 2. Pod mounts a volume using the CSI driver
  # 3. Driver authenticates to Key Vault (using workload identity)
  # 4. Secrets are mounted as files in the pod
  #
  # SECRET ROTATION:
  # - Enabled with 2-minute interval
  # - Driver periodically checks for updates
  # - Updated secrets are automatically remounted
  # - Application must handle file changes (or use sync to K8s secrets)
  #
  # SECURITY BENEFITS:
  # - Secrets never stored in Kubernetes etcd
  # - Centralized secret management in Key Vault
  # - Audit trail in Key Vault logs
  # - Automatic rotation without pod restart
  #
  # REGULATORY ALIGNMENT:
  # - NCUA: Secure secrets management
  # - OSFI B-13: Credential protection
  # - DORA: ICT security controls
  # ===========================================================================
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # ===========================================================================
  # AZURE POLICY INTEGRATION
  # ===========================================================================
  # Enables Azure Policy add-on for AKS, which enforces organizational
  # standards and compliance at scale using Gatekeeper (OPA).
  #
  # WHAT IT DOES:
  # - Deploys Gatekeeper to the cluster
  # - Syncs Azure Policy assignments to Gatekeeper constraints
  # - Audits and/or denies non-compliant resources
  # - Reports compliance status to Azure Policy
  #
  # BUILT-IN POLICIES FOR AKS:
  # - Require specific container images
  # - Enforce resource limits on containers
  # - Prevent privileged containers
  # - Require specific labels
  # - Enforce network policies
  # - Block host namespace sharing
  #
  # REGULATORY ALIGNMENT:
  # - NCUA: Configuration management and compliance
  # - OSFI B-13: Technology standards enforcement
  # - DORA: ICT risk management framework
  # ===========================================================================
  azure_policy_enabled = true

  # ===========================================================================
  # IMAGE CLEANER (2026 COMPLIANCE UPDATE)
  # ===========================================================================
  # Image Cleaner is based on the Eraser project and provides automated
  # removal of unused and vulnerable container images from nodes.
  #
  # WHY THIS MATTERS:
  # - Reduces attack surface by removing unneeded images
  # - Frees node disk space
  # - Removes images with known vulnerabilities
  # - Supports compliance requirements for vulnerability management
  #
  # HOW IT WORKS:
  # 1. Runs on a schedule (default: every 168 hours / 7 days)
  # 2. Uses Trivy to scan images for vulnerabilities
  # 3. Removes images that are:
  #    - Unused (no running container references)
  #    - Vulnerable (based on configurable severity threshold)
  #
  # CONFIGURATION:
  # - interval_hours: How often to scan and clean
  # - Lower intervals = more frequent cleaning = higher resource usage
  # - 168 hours (weekly) balances security and resource usage
  #
  # REGULATORY ALIGNMENT:
  # - NCUA: Vulnerability management and remediation
  # - OSFI B-13: Security patch management
  # - DORA Article 7: ICT systems currency
  # ===========================================================================
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 168 # Weekly scanning

  # ===========================================================================
  # AUTOMATIC UPGRADE CHANNELS
  # ===========================================================================
  # Configures automatic upgrades for the Kubernetes version and node OS.
  #
  # KUBERNETES VERSION UPGRADES (automatic_channel_upgrade):
  # - "stable": Upgrades to latest stable minor version
  # - "rapid": Upgrades as soon as new versions are available
  # - "patch": Only patch version upgrades (e.g., 1.34.1 -> 1.34.2)
  # - "node-image": Only node image updates, not K8s version
  # - "none": Manual upgrades only
  #
  # "stable" SELECTED BECAUSE:
  # - Balances security (timely updates) with stability (tested releases)
  # - Required for future AKS Automatic compatibility
  # - Upgrades happen during maintenance windows
  #
  # NODE OS UPGRADES (node_os_upgrade_channel):
  # - "SecurityPatch": Only security updates (recommended)
  # - "NodeImage": Full node image updates
  # - "Unmanaged": Manual updates only
  #
  # REGULATORY ALIGNMENT:
  # - NCUA: Patch management requirements
  # - OSFI B-13: Technology currency
  # - DORA Article 7: ICT systems kept up to date
  # ===========================================================================
  automatic_channel_upgrade = "stable"
  node_os_upgrade_channel   = "SecurityPatch"

  # ===========================================================================
  # MAINTENANCE WINDOW
  # ===========================================================================
  # Defines when AKS can perform disruptive operations like:
  # - Kubernetes version upgrades
  # - Node image upgrades
  # - Certain add-on updates
  #
  # SCHEDULING CONSIDERATIONS:
  # - Choose low-traffic periods for your application
  # - Ensure operations team is available (even if automated)
  # - Account for time zones
  # - Consider multiple windows for flexibility
  #
  # CURRENT CONFIGURATION:
  # - Sunday 2-4 AM UTC
  # - Typical low-traffic window for many organizations
  # - Provides 2-hour window for operations to complete
  #
  # FOR GLOBAL APPLICATIONS:
  # Consider regional maintenance windows or follow-the-sun scheduling.
  # ===========================================================================
  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [2, 3, 4]
    }
  }

  # ===========================================================================
  # DEPENDENCIES
  # ===========================================================================
  # Explicit dependency on the network role assignment ensures:
  # 1. The AKS identity exists
  # 2. The identity has network permissions
  # 3. THEN the cluster is created
  #
  # Without this, Terraform might try to create the cluster before permissions
  # are applied, causing deployment failures.
  # ===========================================================================
  depends_on = [
    azurerm_role_assignment.aks_network
  ]

  # ===========================================================================
  # LIFECYCLE RULES
  # ===========================================================================
  # Ignore changes to node_count because:
  # - Cluster autoscaler modifies this value
  # - Manual scaling operations modify this value
  # - We don't want Terraform to "correct" these changes
  #
  # IMPORTANT: This only applies to the default pool. User pools with
  # auto-scaling have their own lifecycle management.
  # ===========================================================================
  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count
    ]
  }
}

# =============================================================================
# USER NODE POOL
# =============================================================================
# A separate node pool dedicated to running application workloads.
# This separation from the system pool:
# - Prevents user workloads from impacting system components
# - Allows independent scaling of application capacity
# - Enables different VM sizes for different workload types
# - Supports different OS configurations if needed
#
# SCALING CONFIGURATION:
# - Starts with var.user_node_count nodes
# - Auto-scales between min_count and max_count based on demand
# - Cluster autoscaler considers pending pods and node utilization
# =============================================================================
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_node_vm_size
  node_count            = var.user_node_count
  vnet_subnet_id        = azurerm_subnet.aks.id

  # ---------------------------------------------------------------------------
  # STORAGE CONFIGURATION
  # ---------------------------------------------------------------------------
  # Same configuration as system pool for consistency.
  # Adjust based on workload requirements:
  # - Larger disks for image-heavy workloads
  # - Ephemeral disks for better performance
  # - Premium SSD for IOPS-intensive workloads
  # ---------------------------------------------------------------------------
  os_disk_size_gb = 128
  os_disk_type    = "Managed"

  # ---------------------------------------------------------------------------
  # OPERATING SYSTEM - AZURELINUX
  # ---------------------------------------------------------------------------
  # Same hardened OS as system pool for consistency and security.
  # See system pool comments for AzureLinux benefits.
  # ---------------------------------------------------------------------------
  os_sku = "AzureLinux"

  # ---------------------------------------------------------------------------
  # AUTO-SCALING
  # ---------------------------------------------------------------------------
  # Enabled for user pool to handle variable workload demands.
  #
  # HOW IT WORKS:
  # - Cluster autoscaler monitors pending pods and node utilization
  # - Scales up when pods can't be scheduled due to resource constraints
  # - Scales down when nodes are underutilized for a period
  #
  # CONFIGURATION:
  # - min_count: 2 (minimum for availability across AZs)
  # - max_count: 10 (adjust based on expected peak load)
  #
  # COST OPTIMIZATION:
  # For non-production, consider:
  # - min_count: 1 to reduce baseline costs
  # - Spot instances for cost savings (up to 90% discount)
  # ---------------------------------------------------------------------------
  enable_auto_scaling = true
  min_count           = 2
  max_count           = 10

  # ---------------------------------------------------------------------------
  # NODE LABELS
  # ---------------------------------------------------------------------------
  # Labels for workload scheduling:
  # - nodepool-type=user: Identifies this as a user workload pool
  # - environment=demo: Environment identification
  # - workload=application: General application workloads
  #
  # SCHEDULING EXAMPLE:
  # Use nodeSelector in pod spec to schedule on this pool:
  # spec:
  #   nodeSelector:
  #     nodepool-type: user
  # ---------------------------------------------------------------------------
  node_labels = {
    "nodepool-type" = "user"
    "environment"   = "demo"
    "workload"      = "application"
  }

  tags = var.tags
}

# =============================================================================
# DIAGNOSTIC SETTINGS FOR AKS
# =============================================================================
# Configures which control plane logs and metrics are sent to Log Analytics.
# These logs provide visibility into cluster operations and are essential for:
# - Security monitoring and incident investigation
# - Troubleshooting cluster issues
# - Audit trail for compliance
# - Performance analysis
#
# LOG CATEGORIES:
# ┌──────────────────────────────────────────────────────────────────────────────┐
# │ Category              │ What It Contains                                     │
# ├──────────────────────────────────────────────────────────────────────────────┤
# │ kube-apiserver        │ API server logs (all API calls)                      │
# │ kube-audit            │ Audit logs (detailed request/response)               │
# │ kube-audit-admin      │ Admin-focused audit logs                             │
# │ kube-controller-mgr   │ Controller manager operations                        │
# │ kube-scheduler        │ Pod scheduling decisions                             │
# │ cluster-autoscaler    │ Scaling decisions and operations                     │
# │ guard                 │ Azure AD authentication events                       │
# └──────────────────────────────────────────────────────────────────────────────┘
#
# REGULATORY ALIGNMENT:
# - NCUA Part 748: Audit trail requirements
# - OSFI B-13: Logging and monitoring
# - DORA Article 10: ICT incident detection and logging
# - CIS Kubernetes Benchmark 3.2: Audit logging requirements
#
# 2026 CILIUM NOTE:
# Cilium network policy enforcement logs are captured via kube-audit.
# Configure Cilium Hubble for additional network flow visibility.
# =============================================================================
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name               = "diag-${var.cluster_name}"
  target_resource_id = azurerm_kubernetes_cluster.main.id

  # Send logs to the central Log Analytics workspace
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # ---------------------------------------------------------------------------
  # KUBERNETES API SERVER LOGS
  # ---------------------------------------------------------------------------
  # Records all requests to the Kubernetes API server.
  # Useful for:
  # - Understanding what operations are happening
  # - Debugging API errors
  # - Correlating with application issues
  # ---------------------------------------------------------------------------
  enabled_log {
    category = "kube-apiserver"
  }

  # ---------------------------------------------------------------------------
  # KUBERNETES AUDIT LOGS
  # ---------------------------------------------------------------------------
  # Detailed audit trail of all API requests including:
  # - Who made the request (user/service account)
  # - What was requested (resource, verb)
  # - When it happened
  # - Request and response bodies (at higher audit levels)
  #
  # CRITICAL FOR COMPLIANCE:
  # This is the primary audit trail for Kubernetes operations.
  # ---------------------------------------------------------------------------
  enabled_log {
    category = "kube-audit"
  }

  # ---------------------------------------------------------------------------
  # KUBERNETES AUDIT ADMIN LOGS
  # ---------------------------------------------------------------------------
  # Admin-focused subset of audit logs.
  # Lower volume than full kube-audit.
  # Focuses on significant administrative operations.
  # ---------------------------------------------------------------------------
  enabled_log {
    category = "kube-audit-admin"
  }

  # ---------------------------------------------------------------------------
  # CONTROLLER MANAGER LOGS
  # ---------------------------------------------------------------------------
  # Logs from the controller manager which runs:
  # - Deployment controller
  # - ReplicaSet controller
  # - Node controller
  # - Service account controller
  # - And many others
  #
  # Useful for debugging:
  # - Deployment issues
  # - Pod scheduling problems
  # - Node health issues
  # ---------------------------------------------------------------------------
  enabled_log {
    category = "kube-controller-manager"
  }

  # ---------------------------------------------------------------------------
  # SCHEDULER LOGS
  # ---------------------------------------------------------------------------
  # Logs from the Kubernetes scheduler showing:
  # - Pod scheduling decisions
  # - Why pods couldn't be scheduled
  # - Node selection rationale
  #
  # Useful for debugging:
  # - Pending pods
  # - Resource constraints
  # - Affinity/anti-affinity issues
  # ---------------------------------------------------------------------------
  enabled_log {
    category = "kube-scheduler"
  }

  # ---------------------------------------------------------------------------
  # CLUSTER AUTOSCALER LOGS
  # ---------------------------------------------------------------------------
  # Logs from the cluster autoscaler showing:
  # - Scale up/down decisions
  # - Why scaling did or didn't happen
  # - Node provisioning status
  #
  # Essential for:
  # - Cost optimization analysis
  # - Capacity planning
  # - Debugging scaling issues
  # ---------------------------------------------------------------------------
  enabled_log {
    category = "cluster-autoscaler"
  }

  # ---------------------------------------------------------------------------
  # GUARD LOGS (AZURE AD AUTHENTICATION)
  # ---------------------------------------------------------------------------
  # Logs from the Azure AD integration:
  # - Authentication attempts
  # - Token validation
  # - RBAC decisions
  #
  # Critical for:
  # - Security incident investigation
  # - Access auditing
  # - Troubleshooting authentication issues
  # ---------------------------------------------------------------------------
  enabled_log {
    category = "guard"
  }

  # ---------------------------------------------------------------------------
  # METRICS
  # ---------------------------------------------------------------------------
  # AllMetrics includes:
  # - API server request latency
  # - API server request count
  # - Inflight requests
  # - And other control plane metrics
  #
  # Used for:
  # - Performance monitoring
  # - Capacity planning
  # - SLA tracking
  # ---------------------------------------------------------------------------
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
