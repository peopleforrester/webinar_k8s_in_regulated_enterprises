# Crossplane

> **CNCF Status:** Incubating
> **Category:** Infrastructure as Code
> **Difficulty:** Advanced
> **AKS Compatibility:** Supported

## What It Does

Crossplane extends Kubernetes with Custom Resource Definitions (CRDs) that let you
provision and manage cloud infrastructure -- databases, networks, storage, and more --
using the same kubectl and YAML workflows you already use for application workloads.
Instead of running Terraform from a CI pipeline and hoping the state file stays
consistent, Crossplane runs inside the cluster as a controller, continuously
reconciling your desired infrastructure state against reality. Platform teams define
reusable Compositions that bundle compliance controls into self-service abstractions,
so application developers can request "give me a database" and automatically receive
one configured with encryption, private networking, geo-redundant backup, and audit
logging.

## Regulatory Relevance

| Framework   | Controls Addressed                                                                 |
|-------------|------------------------------------------------------------------------------------|
| NCUA/FFIEC  | Infrastructure provisioning controls, change management for IT systems (Part 748)  |
| SOC 2       | CC7.1 change management, CC6.1 logical access to infrastructure resources          |
| DORA        | Article 11 ICT infrastructure management, Article 9 change management procedures   |
| PCI-DSS     | Req 1.1 network configuration standards, Req 2.2 system configuration standards    |

## Architecture

Crossplane consists of a core runtime (the controller manager and RBAC manager) plus
provider packages that know how to talk to specific cloud APIs. Compositions let
platform teams create higher-level abstractions that bundle multiple cloud resources
into a single claim.

```
┌─────────────────────────────────────────────────────────────────┐
│  AKS Cluster                                                    │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Crossplane Core (Deployment)                            │   │
│  │  ┌──────────────────┐  ┌──────────────────────────────┐  │   │
│  │  │ Controller       │  │ RBAC Manager                 │  │   │
│  │  │ Manager          │  │ (generates ClusterRoles for  │  │   │
│  │  │ (reconciles XRs) │  │  Composite Resources)        │  │   │
│  │  └────────┬─────────┘  └──────────────────────────────┘  │   │
│  └───────────┼──────────────────────────────────────────────┘   │
│              │                                                   │
│  ┌───────────▼──────────────────────────────────────────────┐   │
│  │  Providers (installed as Packages)                       │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │   │
│  │  │ provider-   │  │ provider-    │  │ provider-      │  │   │
│  │  │ azure-      │  │ azure-       │  │ azure-         │  │   │
│  │  │ network     │  │ dbforpostgre │  │ keyvault       │  │   │
│  │  └──────┬──────┘  └──────┬───────┘  └───────┬────────┘  │   │
│  └─────────┼───────────────┼────────────────────┼───────────┘   │
│            │               │                    │                │
└────────────┼───────────────┼────────────────────┼────────────────┘
             │               │                    │
             ▼               ▼                    ▼
      ┌──────────┐   ┌──────────┐         ┌──────────┐
      │ Azure    │   │ Azure    │         │ Azure    │
      │ VNet /   │   │ Database │         │ Key      │
      │ Subnets  │   │ for      │         │ Vault    │
      │          │   │ PostgreSQL│         │          │
      └──────────┘   └──────────┘         └──────────┘
```

The flow works like this:

1. **Platform team** defines an XRD (schema) and Composition (implementation)
2. **Developer** creates a Claim (e.g., "I need a database")
3. **Crossplane** resolves the Claim to a Composite Resource (XR)
4. **Composition** expands the XR into individual Managed Resources
5. **Providers** reconcile each Managed Resource against the Azure API
6. **Continuous reconciliation** detects and corrects drift automatically

### Crossplane vs Terraform

| Aspect              | Crossplane                                | Terraform                              |
|---------------------|-------------------------------------------|----------------------------------------|
| Execution model     | Continuous reconciliation in-cluster      | One-shot apply from CI/CD pipeline     |
| State management    | Kubernetes etcd (built-in HA)             | State file (S3/Azure Blob/Consul)      |
| Drift detection     | Automatic, every poll interval            | Only on `terraform plan`               |
| Self-service        | Claims via kubectl / GitOps               | Wrapper modules + CI pipeline          |
| RBAC                | Native Kubernetes RBAC                    | Separate IAM / Vault policies          |
| Learning curve      | Steep (XRDs, Compositions, Providers)     | Moderate (HCL, modules, state)         |

Both tools are valid choices. Crossplane is stronger when you want Kubernetes-native
GitOps and continuous reconciliation; Terraform is stronger for one-shot provisioning
and broader ecosystem maturity.

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured for the target cluster
- Azure subscription with permissions to create resources

### Install

```bash
# Add the Crossplane Helm repository
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

# Install Crossplane into its own namespace
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace \
  -f values.yaml
```

### Install Azure Providers

```bash
# Apply provider and provider config manifests
kubectl apply -f manifests/provider.yaml

# Wait for providers to become healthy (this downloads and installs provider packages)
kubectl wait provider.pkg.crossplane.io --all \
  --for=condition=Healthy \
  --timeout=300s
```

### Apply Compositions

```bash
# Apply the XRD and Composition for regulated databases
kubectl apply -f manifests/composition.yaml

# Verify the XRD is established
kubectl get xrd regulateddatabases.platform.example.com
```

### Create a Claim

```bash
# A developer creates a claim to request a regulated database
kubectl apply -f manifests/claim.yaml

# Watch the resources being provisioned
kubectl get managed -l crossplane.io/claim-name=team-alpha-db
```

### Verify

```bash
# Check Crossplane core is running
kubectl get pods -n crossplane-system

# Check providers are installed and healthy
kubectl get providers

# Check the composition is available
kubectl get compositions

# Check the XRD is established
kubectl get xrd

# Check claims and their status
kubectl get regulateddatabases --all-namespaces
```

## Key Configuration Decisions

All configuration lives in [`values.yaml`](./values.yaml) with detailed comments
explaining each setting.

### Poll Interval

Crossplane checks each managed resource against the cloud API at a regular interval
(default: 1 minute). Shorter intervals mean faster drift detection but more API calls
(and potential throttling). For regulated environments, the default is appropriate --
drift correction within 60 seconds meets most compliance SLAs.

### Max Reconcile Rate

Controls how many resources Crossplane reconciles per second. The default of 10 is
conservative and avoids Azure API throttling. Production environments with hundreds of
managed resources may need to increase this alongside Azure API rate limit increases.

### Provider Families

This demo uses the Upbound provider family model (`provider-family-azure`) which
installs a shared controller and individual resource providers (network, database,
etc.). This is more efficient than installing a monolithic `provider-azure` because
you only load CRDs for resources you actually use.

### Workload Identity

The provider is configured to use Azure Workload Identity (federated credentials)
rather than storing Azure service principal secrets in the cluster. This eliminates
long-lived credentials and aligns with zero-trust principles.

## EKS / GKE Notes

- **EKS**: Replace `provider-family-azure` with `provider-family-aws`. Use IRSA
  (IAM Roles for Service Accounts) instead of Azure Workload Identity for credential
  injection. Compositions would reference AWS resource types (RDS instead of Azure
  Database for PostgreSQL, VPC instead of VNet).
- **GKE**: Replace `provider-family-azure` with `provider-family-gcp`. Use GKE
  Workload Identity for credential injection. Compositions would reference GCP
  resource types (Cloud SQL instead of Azure Database for PostgreSQL).
- **General**: Crossplane core installation is identical across all providers. The
  XRD (schema) can remain the same -- only the Composition (implementation) changes
  per cloud. This is one of Crossplane's key advantages: portable abstractions with
  provider-specific implementations.

## Certification Relevance

| Certification | Relevance                                                                       |
|---------------|---------------------------------------------------------------------------------|
| **CKA**       | Crossplane exercises cluster architecture concepts: CRDs, controllers, RBAC, and the Kubernetes extension model. Understanding operators and custom resources is directly tested. |
| **KCNA**      | Cloud native architecture and the role of Kubernetes as a universal control plane. Crossplane exemplifies the platform engineering patterns covered in the KCNA curriculum. |
| **CKS**       | RBAC for Crossplane resources, secure credential management via Workload Identity, and network policy for provider pods are relevant to CKS security topics. |

## Learn More

- [Crossplane documentation](https://docs.crossplane.io/)
- [CNCF project page](https://www.cncf.io/projects/crossplane/)
- [GitHub repository](https://github.com/crossplane/crossplane)
- [Upbound Marketplace (providers)](https://marketplace.upbound.io/)
- [Crossplane Compositions guide](https://docs.crossplane.io/latest/concepts/compositions/)
- [Azure provider family](https://marketplace.upbound.io/providers/upbound/provider-family-azure/)
- [Helm chart repository](https://github.com/crossplane/crossplane/tree/master/cluster/charts/crossplane)
