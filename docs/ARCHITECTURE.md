# Architecture

## System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        Azure Cloud                                │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    Resource Group                           │  │
│  │                                                             │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐  │  │
│  │  │   Key Vault  │  │     ACR     │  │  Log Analytics   │  │  │
│  │  │  (Secrets)   │  │  (Images)   │  │  (Monitoring)    │  │  │
│  │  └──────┬───────┘  └──────┬──────┘  └────────┬─────────┘  │  │
│  │         │                 │                    │            │  │
│  │  ┌──────┴─────────────────┴────────────────────┴────────┐  │  │
│  │  │                  VNet (10.0.0.0/16)                   │  │  │
│  │  │  ┌─────────────────────────────────────────────────┐  │  │  │
│  │  │  │              AKS Cluster                         │  │  │  │
│  │  │  │                                                  │  │  │  │
│  │  │  │  ┌──────────┐  ┌───────────┐  ┌──────────────┐ │  │  │  │
│  │  │  │  │  System   │  │   User    │  │   Tool       │ │  │  │  │
│  │  │  │  │ Node Pool │  │ Node Pool │  │  Namespaces  │ │  │  │  │
│  │  │  │  │           │  │           │  │              │ │  │  │  │
│  │  │  │  │ - CoreDNS │  │ - Demo    │  │ T1: falco    │ │  │  │  │
│  │  │  │  │ - Metrics │  │   Apps    │  │     kyverno  │ │  │  │  │
│  │  │  │  │ - Policy  │  │           │  │     trivy    │ │  │  │  │
│  │  │  │  │           │  │           │  │     kubescape│ │  │  │  │
│  │  │  │  │           │  │           │  │ T2: monitor  │ │  │  │  │
│  │  │  │  │           │  │           │  │     argocd   │ │  │  │  │
│  │  │  │  │           │  │           │  │ T3: istio    │ │  │  │  │
│  │  │  │  │           │  │           │  │     harbor   │ │  │  │  │
│  │  │  │  │           │  │           │  │     crosspl  │ │  │  │  │
│  │  │  │  └──────────┘  └───────────┘  └──────────────┘ │  │  │  │
│  │  │  └──────────────────────────────────────────────────┘  │  │  │
│  │  └────────────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## Tiered Architecture

| Tier | Purpose | Tools | Namespace(s) |
|------|---------|-------|--------------|
| 1 | Security Core | Falco, Falcosidekick, Falco Talon, Kyverno, Trivy, Kubescape | falco, kyverno, trivy-system, kubescape |
| 2 | Observability & Delivery | Prometheus Stack (+ Grafana), ArgoCD, External Secrets | monitoring, argocd, external-secrets |
| 3 | Platform Services | Istio, Crossplane, Harbor | istio-system, crossplane-system, harbor |
| 4 | AKS-Managed | Karpenter (Node Autoprovisioning) | kube-system |

See [INSTALL-ORDER.md](INSTALL-ORDER.md) for the dependency graph and install sequence.

## Security Tools Data Flow

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────┐
│   KubeHound      │    │     Falco        │    │     Kyverno          │
│                   │    │                   │    │                      │
│ Ingests cluster   │    │ Monitors syscalls │    │ Validates at         │
│ state, builds     │    │ via eBPF, detects │    │ admission time,      │
│ attack graph      │    │ runtime threats   │    │ blocks non-compliant │
│                   │    │                   │    │ deployments          │
│ Output: Graph DB  │    │ Output: Alerts    │    │ Output: Policy       │
│ (JanusGraph)      │    │ → Falcosidekick   │    │ Reports              │
└─────────────────┘    │ → SIEM/Slack      │    └─────────────────────┘
                        └─────────────────┘

┌─────────────────┐    ┌─────────────────────┐
│  Trivy Operator   │    │     Kubescape       │
│                   │    │                      │
│ Scans images for  │    │ Scans cluster for   │
│ vulnerabilities,  │    │ compliance against  │
│ generates SBOMs   │    │ NSA/SOC2/MITRE/CIS  │
│                   │    │ frameworks           │
│ Output: VulnReps  │    │ Output: Compliance  │
│ + SBOM CRDs       │    │ scores + reports    │
└─────────────────┘    └─────────────────────┘
```

## Platform Tools Data Flow

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────┐
│   Prometheus      │    │     ArgoCD       │    │  External Secrets    │
│                   │    │                   │    │                      │
│ Scrapes metrics   │    │ Watches Git for   │    │ Syncs secrets from   │
│ from all tools    │    │ manifest changes, │    │ Azure Key Vault      │
│ via ServiceMonitor│    │ syncs to cluster  │    │ into K8s Secrets     │
│                   │    │                   │    │                      │
│ Output: Grafana   │    │ Output: Automated │    │ Output: Native K8s   │
│ dashboards + alerts│   │ deployments       │    │ Secret objects       │
└─────────────────┘    └─────────────────┘    └─────────────────────┘

┌─────────────────┐    ┌─────────────────────┐  ┌─────────────────────┐
│     Istio         │    │    Crossplane        │  │     Harbor           │
│                   │    │                      │  │                      │
│ Service mesh with │    │ Provisions Azure     │  │ Container registry   │
│ mTLS, AuthZ       │    │ resources from K8s   │  │ with vulnerability   │
│ policies, traffic │    │ manifests            │  │ scanning and RBAC    │
│ management        │    │                      │  │                      │
│ Output: Encrypted │    │ Output: Managed      │  │ Output: Signed,      │
│ service-to-service│    │ infrastructure       │  │ scanned images       │
└─────────────────┘    └─────────────────────┘  └─────────────────────┘
```

## Network Architecture

| Component | CIDR | Purpose |
|-----------|------|---------|
| VNet | 10.0.0.0/16 | Main virtual network |
| AKS Subnet | 10.0.0.0/22 | AKS node network (1,022 IPs) |
| Services Subnet | 10.0.4.0/24 | Azure service endpoints |
| K8s Service CIDR | 10.1.0.0/16 | Kubernetes service IPs |
| DNS Service IP | 10.1.0.10 | CoreDNS service address |

## AKS Security Features

| Feature | Status | Purpose |
|---------|--------|---------|
| Azure CNI | Enabled | Network plugin with Azure network policies |
| Network Policy | Azure | Kubernetes network policy enforcement |
| OIDC Issuer | Enabled | Workload identity federation |
| Workload Identity | Enabled | Pod-level Azure AD authentication |
| Azure Policy | Enabled | Azure-managed policy enforcement |
| Microsoft Defender | Enabled | Container threat detection |
| Key Vault CSI | Enabled | Secrets mounted from Key Vault |
| Diagnostic Logs | Enabled | API server, audit, controller, scheduler logs |
| Auto-Upgrade | Patch | Automatic security patch upgrades |

## Demo Workload Comparison

| Aspect | Vulnerable App | Compliant App |
|--------|---------------|---------------|
| Image | nginx:latest | nginx:1.25.4 |
| User | root (UID 0) | nginx (UID 101) |
| Privileged | true | false |
| Root FS | writable | read-only |
| Capabilities | all | dropped ALL |
| Resources | none set | CPU/memory limits |
| Network Policy | none | restrictive ingress/egress |
| Service Account | cluster-wide secrets access | automountServiceAccountToken: false |
| Seccomp | none | RuntimeDefault |
