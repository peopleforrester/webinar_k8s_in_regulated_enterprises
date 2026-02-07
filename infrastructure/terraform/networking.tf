# ==============================================================================
# NETWORKING INFRASTRUCTURE FOR AKS
# ==============================================================================
#
# PURPOSE:
# This file defines the network foundation for the AKS cluster, implementing
# a secure network architecture suitable for regulated financial institutions.
#
# NETWORK ARCHITECTURE OVERVIEW:
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        Virtual Network (10.0.0.0/16)                         │
# │                                                                              │
# │  ┌────────────────────────────────┐  ┌────────────────────────────────┐    │
# │  │      AKS Subnet (10.0.0.0/22)  │  │  Services Subnet (10.0.4.0/24) │    │
# │  │                                │  │                                 │    │
# │  │  ┌──────────┐  ┌──────────┐   │  │  Reserved for:                  │    │
# │  │  │  Node 1  │  │  Node 2  │   │  │  - Private Endpoints            │    │
# │  │  │          │  │          │   │  │  - Internal Load Balancers      │    │
# │  │  └──────────┘  └──────────┘   │  │  - Azure Bastion (if needed)    │    │
# │  │                                │  │                                 │    │
# │  │  Service Endpoints:            │  └────────────────────────────────┘    │
# │  │  - Microsoft.KeyVault          │                                         │
# │  │  - Microsoft.ContainerRegistry │                                         │
# │  │  - Microsoft.Storage           │                                         │
# │  │                                │                                         │
# │  │  NSG: Ingress/Egress Controls  │                                         │
# │  └────────────────────────────────┘                                         │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# IP ADDRESS ALLOCATION:
# ┌──────────────────────────────────────────────────────────────────────────────┐
# │ CIDR Block       │ Purpose                    │ Usable IPs │ Defined In      │
# ├──────────────────────────────────────────────────────────────────────────────┤
# │ 10.0.0.0/16      │ VNet address space         │ 65,536     │ This file       │
# │ 10.0.0.0/22      │ AKS nodes                  │ 1,022      │ This file       │
# │ 10.0.4.0/24      │ Azure services             │ 254        │ This file       │
# │ 10.1.0.0/16      │ Kubernetes Services        │ 65,536     │ aks.tf          │
# │ 192.168.0.0/16   │ Pod CIDR (Overlay)         │ 65,536     │ aks.tf          │
# └──────────────────────────────────────────────────────────────────────────────┘
#
# REGULATORY ALIGNMENT:
# - NCUA Part 748: Network segmentation for data protection
# - OSFI B-13: Network security controls and monitoring
# - DORA Article 6: ICT network security requirements
# - CIS Kubernetes Benchmark 5.4: Network policies and segmentation
#
# 2026 NETWORK UPDATES:
# - Cilium CNI provides eBPF-based network policies (see aks.tf)
# - Azure CNI Overlay reduces IP consumption in AKS subnet
# - Service Endpoints provide secure, private connectivity to PaaS services
# ==============================================================================

# =============================================================================
# VIRTUAL NETWORK
# =============================================================================
# The Virtual Network (VNet) is the fundamental network building block in Azure.
# All resources in this deployment communicate through this VNet, and it provides
# isolation from other Azure resources and the public internet.
#
# DESIGN DECISIONS:
#
# 1. ADDRESS SPACE (/16):
#    - Provides 65,536 IP addresses
#    - Large enough for future growth (additional node pools, services)
#    - Allows for multiple /22 subnets for different workload types
#
# 2. SINGLE VNET APPROACH:
#    - Simpler architecture for this demo
#    - Production may use hub-spoke topology with Azure Firewall
#    - Consider VNet peering for shared services (AD DS, logging)
#
# 3. NO CUSTOM DNS:
#    - Uses Azure-provided DNS (168.63.129.16)
#    - For hybrid environments, configure custom DNS servers for on-prem resolution
#
# REGULATORY CONSIDERATIONS:
# - Network isolation is foundational to regulatory compliance
# - All network traffic should be encrypted in transit
# - Consider Network Watcher for traffic analytics and flow logs
# =============================================================================
resource "azurerm_virtual_network" "main" {
  # Naming: vnet-<cluster-name>
  # Using cluster name creates a clear association between network and AKS cluster
  name                = "vnet-${var.cluster_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # ---------------------------------------------------------------------------
  # ADDRESS SPACE
  # ---------------------------------------------------------------------------
  # The overall IP range for this VNet. All subnets must be within this range.
  #
  # 10.0.0.0/16 provides:
  # - Range: 10.0.0.0 to 10.0.255.255
  # - 65,536 total IP addresses
  # - Commonly used for isolated cloud networks
  #
  # AVOIDING CONFLICTS:
  # - Ensure this range doesn't overlap with on-premises networks
  # - Don't overlap with other VNets you need to peer with
  # - The Kubernetes service CIDR (10.1.0.0/16) intentionally doesn't overlap
  # ---------------------------------------------------------------------------
  address_space = ["10.0.0.0/16"]

  tags = var.tags
}

# =============================================================================
# AKS NODE SUBNET
# =============================================================================
# This subnet hosts the AKS cluster nodes (VMs). With Azure CNI Overlay,
# pods get IPs from a separate overlay network (192.168.0.0/16), so this
# subnet only needs to accommodate node IPs, not pod IPs.
#
# SIZING CALCULATION:
# /22 = 1,024 addresses (1,022 usable after Azure reserves 5)
#
# Node capacity example:
# - 3 system nodes + 10 user nodes = 13 nodes
# - With auto-scaling max of 100 nodes, still only 100 IPs needed
# - /22 provides significant growth headroom
#
# AZURE CNI OVERLAY ADVANTAGE (2026 BEST PRACTICE):
# Without overlay (traditional Azure CNI):
# - Each pod needs a VNet IP
# - 30 pods per node * 100 nodes = 3,000 IPs minimum
# - Would require /20 or larger subnet
#
# With overlay (our configuration):
# - Only nodes consume VNet IPs
# - Pods use overlay network (192.168.0.0/16)
# - /22 is more than sufficient
#
# SERVICE ENDPOINTS EXPLAINED:
# Service endpoints provide optimized, private connectivity to Azure PaaS
# services. Traffic goes over the Azure backbone, not the public internet.
# =============================================================================
resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name

  # ---------------------------------------------------------------------------
  # ADDRESS PREFIX
  # ---------------------------------------------------------------------------
  # 10.0.0.0/22 provides 1,022 usable IPs (Azure reserves 5 per subnet):
  # - 10.0.0.0: Network address
  # - 10.0.0.1: Azure gateway
  # - 10.0.0.2-3: Azure DNS
  # - 10.0.3.255: Broadcast
  #
  # Usable range: 10.0.0.4 to 10.0.3.254
  # ---------------------------------------------------------------------------
  address_prefixes = ["10.0.0.0/22"]

  # ---------------------------------------------------------------------------
  # SERVICE ENDPOINTS
  # ---------------------------------------------------------------------------
  # Service endpoints extend your VNet identity to Azure services, enabling
  # secure, direct connectivity over the Azure backbone network.
  #
  # SECURITY BENEFITS:
  # - Traffic never leaves the Azure network
  # - Resources can be locked to only accept traffic from this VNet
  # - No public IP exposure needed for PaaS services
  #
  # ENDPOINTS CONFIGURED:
  #
  # 1. Microsoft.KeyVault:
  #    - Allows Key Vault to restrict access to this subnet
  #    - Pods can access secrets without public internet
  #    - Required for Key Vault CSI driver to function securely
  #
  # 2. Microsoft.ContainerRegistry:
  #    - Secure image pulls from ACR
  #    - Can configure ACR to deny public access
  #    - Reduces image pull latency
  #
  # 3. Microsoft.Storage:
  #    - Required for persistent volumes using Azure Files
  #    - Enables secure backup/restore operations
  #    - Log export to storage accounts
  #
  # REGULATORY ALIGNMENT:
  # - NCUA: Data in transit protection via private connectivity
  # - OSFI B-13: Network segmentation and secure communication
  # - DORA: Secure data transmission requirements
  # ---------------------------------------------------------------------------
  service_endpoints = [
    "Microsoft.KeyVault",
    "Microsoft.ContainerRegistry",
    "Microsoft.Storage"
  ]
}

# =============================================================================
# SERVICES SUBNET
# =============================================================================
# A separate subnet reserved for Azure services that may be deployed alongside
# the AKS cluster. This separation follows network segmentation best practices.
#
# POTENTIAL USES:
# - Private Endpoints for Azure SQL, Cosmos DB, or other PaaS services
# - Internal Load Balancers for services that shouldn't be in the AKS subnet
# - Azure Bastion for secure VM access (if jump box is needed)
# - Application Gateway for WAF and ingress (alternative to nginx)
# - Azure Firewall for egress control (in hub-spoke topology)
#
# WHY SEPARATE SUBNET:
# - Different NSG rules may apply
# - Private endpoints require delegation in some cases
# - Clearer network topology for troubleshooting
# - Enables different service endpoint configurations
# =============================================================================
resource "azurerm_subnet" "services" {
  name                 = "snet-services"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name

  # ---------------------------------------------------------------------------
  # ADDRESS PREFIX
  # ---------------------------------------------------------------------------
  # 10.0.4.0/24 provides 254 usable IPs
  # - Positioned after the /22 AKS subnet (which ends at 10.0.3.255)
  # - Sufficient for most service scenarios
  # - Can add more /24 subnets as needed (10.0.5.0/24, 10.0.6.0/24, etc.)
  # ---------------------------------------------------------------------------
  address_prefixes = ["10.0.4.0/24"]
}

# =============================================================================
# NETWORK SECURITY GROUP (NSG)
# =============================================================================
# NSGs are stateful firewalls that filter network traffic to and from Azure
# resources. They contain security rules that allow or deny traffic based on
# source, destination, port, and protocol.
#
# DEFAULT BEHAVIOR:
# Azure NSGs include default rules that:
# - Allow all traffic within the VNet (priority 65000)
# - Allow inbound from Azure Load Balancer (priority 65001)
# - Deny all other inbound traffic (priority 65500)
# - Allow all outbound to VNet (priority 65000)
# - Allow all outbound to Internet (priority 65001)
# - Deny all other outbound traffic (priority 65500)
#
# SECURITY HARDENING:
# For production regulated environments, add explicit rules for:
# - Allowed ingress ports (443 for HTTPS, possibly 80 for redirect)
# - Egress restrictions (only allow necessary destinations)
# - Inter-subnet traffic controls
#
# REGULATORY REQUIREMENTS:
# - NCUA Part 748: Access controls for information systems
# - OSFI B-13: Network perimeter security
# - DORA Article 6: ICT network security controls
# - PCI DSS 1.2: Firewall configuration requirements
#
# 2026 NOTE - CILIUM NETWORK POLICIES:
# The Cilium CNI (configured in aks.tf) provides Layer 7 network policies
# INSIDE the cluster. NSGs operate at Layer 4 on the Azure network level.
# Both are needed for defense in depth:
# - NSG: Controls traffic entering/leaving the VNet
# - Cilium: Controls traffic between pods within the cluster
# =============================================================================
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-${var.cluster_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # ---------------------------------------------------------------------------
  # SECURITY RULES
  # ---------------------------------------------------------------------------
  # This NSG currently uses only Azure's default rules.
  #
  # RECOMMENDED ADDITIONS FOR PRODUCTION:
  #
  # 1. Allow HTTPS ingress:
  #    security_rule {
  #      name                       = "AllowHTTPS"
  #      priority                   = 100
  #      direction                  = "Inbound"
  #      access                     = "Allow"
  #      protocol                   = "Tcp"
  #      source_port_range          = "*"
  #      destination_port_range     = "443"
  #      source_address_prefix      = "Internet"
  #      destination_address_prefix = "*"
  #    }
  #
  # 2. Deny all other Internet ingress (lower priority than allow rules):
  #    security_rule {
  #      name                       = "DenyInternetInbound"
  #      priority                   = 4000
  #      direction                  = "Inbound"
  #      access                     = "Deny"
  #      protocol                   = "*"
  #      source_port_range          = "*"
  #      destination_port_range     = "*"
  #      source_address_prefix      = "Internet"
  #      destination_address_prefix = "*"
  #    }
  #
  # 3. Restrict egress to necessary services only (advanced):
  #    security_rule {
  #      name                       = "AllowAzureCloud"
  #      priority                   = 100
  #      direction                  = "Outbound"
  #      access                     = "Allow"
  #      protocol                   = "*"
  #      source_port_range          = "*"
  #      destination_port_range     = "*"
  #      source_address_prefix      = "*"
  #      destination_address_prefix = "AzureCloud"
  #    }
  # ---------------------------------------------------------------------------

  tags = var.tags
}

# =============================================================================
# NSG SUBNET ASSOCIATION
# =============================================================================
# Associates the NSG with the AKS subnet. This ensures all traffic to/from
# the AKS nodes passes through the NSG rules.
#
# IMPORTANT NOTES:
# - An NSG can be associated with multiple subnets
# - A subnet can only have one NSG associated
# - Rules apply to all NICs in the subnet
# - AKS-managed load balancers will automatically create NSG rules for services
#
# AZURE AUTOMATIC RULES:
# When you create a LoadBalancer service in Kubernetes, AKS automatically
# creates NSG rules to allow traffic to the service port. These rules have
# high priority numbers (e.g., 500) and are managed by AKS.
#
# CAUTION:
# - Don't manually delete AKS-created rules
# - Use lower priority numbers (100-300) for your custom rules
# - Test custom rules thoroughly before production
# =============================================================================
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}
