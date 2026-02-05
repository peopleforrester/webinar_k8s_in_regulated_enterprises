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
│  │  │  │  │  System   │  │   User    │  │   Security   │ │  │  │  │
│  │  │  │  │ Node Pool │  │ Node Pool │  │  Namespaces  │ │  │  │  │
│  │  │  │  │           │  │           │  │              │ │  │  │  │
│  │  │  │  │ - CoreDNS │  │ - Demo    │  │ - falco      │ │  │  │  │
│  │  │  │  │ - Metrics │  │   Apps    │  │ - kyverno    │ │  │  │  │
│  │  │  │  │ - Policy  │  │           │  │ - trivy      │ │  │  │  │
│  │  │  │  │           │  │           │  │ - kubescape  │ │  │  │  │
│  │  │  │  └──────────┘  └───────────┘  └──────────────┘ │  │  │  │
│  │  │  └──────────────────────────────────────────────────┘  │  │  │
│  │  └────────────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

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
