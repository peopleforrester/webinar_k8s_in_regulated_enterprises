<!-- ABOUTME: Companion guide for Karpenter node autoscaling on AKS regulated clusters. -->
<!-- ABOUTME: Covers AKS-managed Karpenter provider, NodePool CRDs, and capacity planning. -->

# Karpenter

> **CNCF Status:** Incubating (originally AWS, donated to CNCF)
> **Category:** Node Autoscaling
> **Difficulty:** Intermediate
> **AKS Compatibility:** Preview (AKS Karpenter provider is in public preview)

## What It Does

Karpenter is a high-performance Kubernetes node autoscaler that provisions compute
capacity directly in response to unschedulable pods. Unlike cluster-autoscaler, which
scales existing node pools up and down, Karpenter provisions individual nodes with the
optimal VM size for each pending workload -- eliminating the need to pre-define node
pool configurations. On AKS, Karpenter uses the `karpenter-provider-azure` to provision
Azure VMs via VMSS Flex, picking the best SKU from a set of allowed instance families.

## How Karpenter Differs from Cluster-Autoscaler

| Aspect | Cluster-Autoscaler | Karpenter |
|--------|-------------------|-----------|
| **Scaling unit** | Scales existing node pools (VMSS) | Provisions individual nodes with optimal VM size |
| **VM size selection** | Fixed per node pool | Chooses from allowed instance families per workload |
| **Provisioning speed** | Minutes (VMSS scaling) | Seconds (direct VM provisioning via VMSS Flex) |
| **Bin-packing** | Limited (must fit node pool shape) | Optimal (selects VM size matching pod requirements) |
| **Consolidation** | Does not consolidate | Actively consolidates underutilized nodes |
| **Configuration** | Azure VMSS + K8s ConfigMap | Kubernetes-native CRDs (NodePool, AKSNodeClass) |
| **Cost optimization** | Manual (separate node pools for spot) | Native (capacity type as a NodePool requirement) |

For regulated environments, Karpenter's consolidation and right-sizing capabilities
translate directly into FinOps cost management while maintaining capacity guarantees
required by resilience frameworks.

## Regulatory Relevance

| Framework   | Controls Addressed                                                                  |
|-------------|------------------------------------------------------------------------------------|
| NCUA/FFIEC  | Operational resilience, capacity planning to prevent service degradation             |
| SOC 2       | CC7.5 Availability -- automated capacity management prevents outages                |
| DORA        | Article 11 -- ICT capacity management, ensuring systems scale to meet demand        |
| PCI-DSS     | 12.3.3 -- capacity planning to ensure security systems maintain coverage at scale   |

### How Karpenter Supports Capacity Compliance

Regulators expect financial institutions to demonstrate that critical systems can handle
peak loads without degradation. Karpenter provides:

1. **Automated capacity response** -- Pods never stay unschedulable for more than seconds,
   not minutes. This directly addresses DORA Article 11 requirements for ICT systems to
   "maintain adequate capacity to meet business requirements."
2. **Resource limits per NodePool** -- Hard caps on CPU and memory prevent runaway scaling.
   These limits map to capacity budgets that auditors can review.
3. **Disruption budgets** -- Control how aggressively Karpenter consolidates nodes,
   preventing bulk node termination that could impact service availability.
4. **Workload isolation** -- Separate NodePools for regulated vs. non-regulated workloads
   ensure sensitive applications run on dedicated, on-demand compute.

## Architecture

Karpenter on AKS runs as a managed component. The controller watches for unschedulable
pods and provisions Azure VMs to satisfy their resource and scheduling requirements.

```
                                        ┌─────────────────────────┐
                                        │   Git / Kubectl Apply   │
                                        │                         │
                                        │  NodePool + AKSNodeClass│
                                        │  CRD definitions        │
                                        └────────────┬────────────┘
                                                     │
                                                     v
┌───────────────────────────────────────────────────────────────────────┐
│  AKS Control Plane                                                    │
│                                                                       │
│  ┌──────────────────┐     ┌──────────────────┐                        │
│  │  kube-scheduler   │     │  Karpenter       │                        │
│  │                   │     │  Controller      │                        │
│  │  Marks pods as    │────>│                  │                        │
│  │  unschedulable    │     │  1. Groups pods  │                        │
│  └──────────────────┘     │  2. Selects SKU  │                        │
│                            │  3. Provisions VM│                        │
│                            └────────┬─────────┘                        │
│                                     │                                  │
└─────────────────────────────────────┼──────────────────────────────────┘
                                      │ Azure API
                                      v
┌─────────────────────────────────────────────────────────────────────┐
│  Azure Resource Manager                                             │
│                                                                     │
│  ┌───────────────────┐  ┌───────────────────┐                       │
│  │  VMSS Flex         │  │  VMSS Flex         │                       │
│  │  (on-demand)       │  │  (spot)            │                       │
│  │                    │  │                    │                       │
│  │  D4s_v5, D8s_v5   │  │  D4s_v5, D8s_v5   │                       │
│  │  E4s_v5, E8s_v5   │  │  D4as_v5, D8as_v5 │                       │
│  └────────┬──────────┘  └────────┬──────────┘                       │
│           │                      │                                   │
└───────────┼──────────────────────┼───────────────────────────────────┘
            │                      │
            v                      v
┌──────────────────┐  ┌──────────────────┐
│  AKS Node        │  │  AKS Node        │
│  (regulated)     │  │  (non-regulated) │
│                  │  │                  │
│  Labeled:        │  │  Tainted:        │
│  tier=regulated  │  │  spot=true       │
│  On-demand only  │  │  Cost-optimized  │
└──────────────────┘  └──────────────────┘
```

**Event flow:**

1. Pods are submitted but cannot be scheduled (insufficient capacity or no matching nodes)
2. kube-scheduler marks pods as `Unschedulable`
3. Karpenter controller detects unschedulable pods
4. Karpenter groups pods by scheduling constraints (node selectors, affinity, tolerations)
5. Karpenter selects the optimal Azure VM SKU from the allowed set in the matching NodePool
6. Azure provisions a VM via VMSS Flex (seconds, not minutes)
7. The new node joins the cluster, kubelet registers, and pods are scheduled

**Consolidation flow (cost optimization):**

1. Karpenter continuously evaluates node utilization
2. If pods on an underutilized node can fit on other existing nodes, Karpenter cordons
   and drains the underutilized node
3. The empty node is terminated, reducing cost
4. Disruption budgets prevent too many nodes from being removed simultaneously

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Azure CLI 2.x with the `aks-preview` extension installed
- kubectl configured for the target cluster
- The AKS cluster must use VMSS Flex (not VMSS Uniform) for Karpenter compatibility

### Important: AKS Karpenter Is a Managed Feature

Unlike other tools in this repository that you install via Helm, AKS Karpenter is a
**managed AKS feature**. You enable it on the cluster -- Microsoft manages the controller
lifecycle, upgrades, and availability. You do not install a Helm chart.

Your configuration surface is:

1. **Cluster-level**: Enable the node provisioning feature on the AKS cluster
2. **CRD-level**: Apply `NodePool` and `AKSNodeClass` resources to define provisioning rules

### Enable Karpenter on AKS

#### Option A: Azure CLI

```bash
# Ensure the aks-preview extension is installed and up-to-date
az extension add --name aks-preview --upgrade

# Register the NodeAutoProvisioningPreview feature flag
az feature register --namespace Microsoft.ContainerService \
  --name NodeAutoProvisioningPreview

# Wait for registration to complete (may take several minutes)
az feature show --namespace Microsoft.ContainerService \
  --name NodeAutoProvisioningPreview \
  --query "properties.state" -o tsv

# Enable Karpenter on an existing cluster
az aks update \
  --resource-group rg-aks-regulated-demo \
  --name aks-regulated-demo \
  --enable-node-provisioning
```

#### Option B: Terraform

```hcl
resource "azurerm_kubernetes_cluster" "main" {
  # ... existing configuration ...

  # Enable Karpenter (AKS Node Auto Provisioning)
  node_provisioning_enabled = true
}
```

### Apply NodePool and AKSNodeClass

```bash
# Apply the on-demand NodePool for regulated workloads
kubectl apply -f manifests/node-pool.yaml

# Apply the spot NodePool for non-sensitive workloads (optional)
kubectl apply -f manifests/node-pool-spot.yaml
```

### Verify

```bash
# Confirm Karpenter controller is running in the managed namespace
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter

# Check NodePool resources are accepted
kubectl get nodepools

# Check AKSNodeClass resources are accepted
kubectl get aksnodeclasses

# View Karpenter provisioning decisions
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50

# Watch Karpenter respond to a pending pod (in a separate terminal)
kubectl get events --field-selector reason=Provisioning --watch
```

### Test Provisioning

```bash
# Create a deployment that requests more capacity than currently available
kubectl create deployment karpenter-test \
  --image=mcr.microsoft.com/azurelinux/base/nginx:1.25 \
  --replicas=5

# Set resource requests to trigger provisioning
kubectl set resources deployment karpenter-test \
  --requests=cpu=500m,memory=512Mi

# Watch Karpenter provision new nodes
kubectl get nodes --watch
```

## Key Configuration Decisions

Configuration is split between the managed feature (cluster-level) and CRD resources
(NodePool, AKSNodeClass) in the [`manifests/`](./manifests/) directory.

The [`values.yaml`](./values.yaml) in this directory is a **reference document** showing
the Karpenter provider settings that AKS manages on your behalf. It is not used for
installation but serves as educational documentation of the available configuration knobs.

### NodePool Design: Regulated vs. Non-Regulated

This repository defines two NodePools:

- **`regulated-workloads`** ([`manifests/node-pool.yaml`](./manifests/node-pool.yaml)):
  On-demand instances only. D-series and E-series VMs. Hard resource limits. Conservative
  disruption settings. Pods with `workload-tier: regulated` land here.

- **`cost-optimized`** ([`manifests/node-pool-spot.yaml`](./manifests/node-pool-spot.yaml)):
  Spot instances for dev/test and non-sensitive batch workloads. Aggressive consolidation.
  Tainted to prevent regulated workloads from scheduling unless they explicitly tolerate.

### Instance Family Selection

For regulated workloads, we restrict to D-series (general purpose) and E-series
(memory-optimized) VMs. These families offer:

- Consistent performance (no burstable B-series)
- Predictable pricing for capacity planning
- Premium storage support for persistent workloads
- Availability in all Azure regions

### Disruption Budgets

Karpenter's disruption budgets control how aggressively nodes are consolidated or
replaced. For regulated workloads, we use conservative settings:

- Maximum 10% of nodes disrupted simultaneously
- No disruption during business hours (configurable schedule)
- Consolidation policy set to `WhenEmptyOrUnderutilized` (not `WhenEmpty` alone)

These settings balance cost optimization with the availability requirements of
DORA Article 11 and SOC 2 CC7.5.

## EKS / GKE Notes

### EKS (Most Mature Provider)

Karpenter was originally built by AWS for EKS and remains the most mature provider.
Key differences from AKS:

- **Installation**: Installed via Helm chart (`karpenter/karpenter`) -- not managed by the
  cloud provider. You manage the controller lifecycle.
- **Node class**: `EC2NodeClass` instead of `AKSNodeClass`. Configures AMI family,
  security groups, subnets, and instance profiles.
- **Instance types**: Uses EC2 instance type names (m5.xlarge, c6i.2xlarge, etc.)
- **Spot handling**: Native EC2 Spot integration with interruption handling
- **IRSA**: Uses IAM Roles for Service Accounts for AWS API permissions

### GKE (Alternative: GKE Autopilot / Node Auto-Provisioning)

GKE does not use Karpenter. Instead, GKE offers:

- **Node Auto-Provisioning (NAP)**: Similar concept -- creates node pools automatically
  based on pending pod requirements. Configures machine types and accelerators.
- **GKE Autopilot**: Fully managed node infrastructure where Google handles all node
  provisioning, scaling, and security. The closest analog to Karpenter's vision.
- **Difference**: NAP still creates node pools (VMSS-equivalent), while Karpenter on
  EKS/AKS provisions individual nodes.

### Cross-Provider Portability

NodePool resources are provider-agnostic -- the `spec.template.spec.requirements` and
disruption settings are the same across providers. The provider-specific resource
(AKSNodeClass, EC2NodeClass) is the only part that changes.

## Certification Relevance

| Certification | Relevance                                                                       |
|---------------|---------------------------------------------------------------------------------|
| **CKA**       | Node management, scheduling constraints, taints/tolerations, resource management -- all foundational to understanding Karpenter's behavior. |
| **KCNA**      | Autoscaling concepts, cluster architecture, and understanding how Kubernetes provisions compute capacity. |
| **CKS**       | Workload isolation via node selectors, taints, and dedicated node pools for security-sensitive workloads. |
| **CKAD**      | Resource requests/limits, scheduling constraints, and pod affinity/anti-affinity that drive Karpenter's provisioning decisions. |

## Learn More

- [Karpenter documentation](https://karpenter.sh/docs/)
- [CNCF project page](https://www.cncf.io/projects/karpenter/)
- [GitHub repository](https://github.com/kubernetes-sigs/karpenter)
- [AKS Node Auto Provisioning (Karpenter) docs](https://learn.microsoft.com/en-us/azure/aks/node-autoprovision)
- [karpenter-provider-azure repository](https://github.com/Azure/karpenter-provider-azure)
- [Karpenter best practices](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
- [NodePool API reference](https://karpenter.sh/docs/concepts/nodepools/)
- [AKSNodeClass API reference](https://github.com/Azure/karpenter-provider-azure/blob/main/docs/aksnodeclass.md)
