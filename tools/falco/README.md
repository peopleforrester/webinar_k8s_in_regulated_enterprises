# Falco

> **CNCF Status:** Graduated
> **Category:** Runtime Security
> **Difficulty:** Intermediate
> **AKS Compatibility:** Supported

## What It Does

Falco monitors Linux syscalls via eBPF to detect runtime threats in containers and
Kubernetes workloads in real time. It operates at the kernel level, watching for
anomalous behavior that static scanning and admission control cannot catch. Falco
detects container escapes, privilege escalation, credential theft, suspicious process
execution, and unexpected network connections -- providing the runtime layer of a
defense-in-depth security strategy.

## Regulatory Relevance

| Framework   | Controls Addressed                                                             |
|-------------|--------------------------------------------------------------------------------|
| NCUA/FFIEC  | Continuous monitoring of systems for unauthorized access (Part 748)            |
| SOC 2       | CC6.1 logical access security, CC7.2 anomaly detection in system operations   |
| DORA        | ICT incident detection and anomalous activity monitoring (Article 10)         |
| PCI-DSS     | 10.6.1 log monitoring, review of security events and audit trails             |

## Architecture

Falco runs as a **DaemonSet** on every node in the cluster, ensuring complete coverage
with no blind spots. Each Falco pod attaches to the host kernel using the `modern_ebpf`
driver (CO-RE / Compile Once Run Everywhere) to capture syscalls without requiring
kernel headers or module compilation.

```
┌─────────────────────────────────────────────────────────┐
│  AKS Node                                               │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │ App Pod  │  │ App Pod  │  │ App Pod  │              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
│       │syscalls      │              │                    │
│  ┌────▼──────────────▼──────────────▼───────────────┐   │
│  │  Linux Kernel (eBPF probes)                      │   │
│  └────────────────────┬─────────────────────────────┘   │
│                       │                                  │
│  ┌────────────────────▼─────────────────────────────┐   │
│  │  Falco DaemonSet Pod                             │   │
│  │  ┌────────────┐  ┌──────────┐  ┌──────────────┐ │   │
│  │  │ modern_ebpf│→ │ Rules    │→ │ JSON Output  │ │   │
│  │  │ driver     │  │ Engine   │  │ (stdout/gRPC)│ │   │
│  │  └────────────┘  └──────────┘  └──────┬───────┘ │   │
│  └───────────────────────────────────────┼──────────┘   │
│                                          │               │
│  ┌───────────────────────────────────────▼──────────┐   │
│  │  Falcosidekick (Deployment)                      │   │
│  │  Routes alerts to Slack, SIEM, PagerDuty, etc.   │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

Events flow: **kernel syscalls** -> **eBPF probes** -> **Falco rules engine** ->
**JSON-formatted alerts** -> **Falcosidekick** for routing to external systems.

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured for the target cluster

### Install

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  -f values.yaml
```

For production deployments, layer the production overrides:

```bash
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  -f values.yaml \
  -f values-production.yaml
```

### Verify

```bash
# Confirm all Falco pods are running (one per node)
kubectl get pods -n falco -l app.kubernetes.io/name=falco -o wide

# Check Falco logs for successful startup
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20

# Stream live security events
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# Access Falcosidekick UI (if enabled)
kubectl port-forward -n falco svc/falcosidekick-ui 2802:2802
```

## Key Configuration Decisions

All configuration lives in [`values.yaml`](./values.yaml) (demo/dev) and
[`values-production.yaml`](./values-production.yaml) (production overrides).

### Driver: `modern_ebpf`

The driver determines how Falco captures syscalls from the kernel. We use `modern_ebpf`
because it works on kernel 5.8+ without requiring kernel headers or module compilation.
AKS nodes run Ubuntu with 5.15+ kernels, making this the best choice. Alternatives
(`kmod`, legacy `ebpf`) require additional host dependencies and are being deprecated
in Falco 0.43.0. The `auto` fallback mode is avoided in production to prevent
unpredictable behavior.

### Custom Rules

Financial-services-specific detection rules are defined in
[`custom-rules/financial-services.yaml`](./custom-rules/financial-services.yaml) and
include:

- **Financial data file access** -- detects reads of files matching PII/PCI patterns
- **Kubernetes secrets API access** -- catches credential theft via API calls
- **Service account token reads** -- flags unexpected token access from shells or curl
- **Crypto mining detection** -- identifies known miner processes and stratum protocols
- **Non-standard outbound connections** -- detects potential data exfiltration
- **Privilege escalation attempts** -- catches sudo/su usage and /etc/shadow writes
- **Interactive shell detection** -- alerts on TTY-attached shells in containers
- **Database credential access** -- monitors reads of .pgpass, .my.cnf, and similar files

All custom rules include MITRE ATT&CK tags for incident classification.

### Output Format

JSON output is enabled with tags included, making events parseable by SIEM systems and
enabling automatic classification per DORA Article 12. The gRPC server uses a Unix
socket for low-latency, secure communication with Falcosidekick.

### Event Drop Handling

Dropped syscall events represent gaps in security monitoring. Demo configuration
tolerates 10% drops with logging; production drops the threshold to 1% and terminates
the Falco process on breach, forcing Kubernetes to restart the pod and triggering
investigation alerts.

## EKS / GKE Notes

- **EKS**: The `modern_ebpf` driver works on Amazon Linux 2 and Bottlerocket nodes
  (kernel 5.10+). EKS-managed node groups handle kernel compatibility automatically.
  No driver changes needed.
- **GKE**: Container-Optimized OS (COS) nodes restrict kernel module loading, making
  `modern_ebpf` the only viable driver. GKE Autopilot clusters impose additional
  constraints on DaemonSet privileges; standard GKE clusters are recommended.
- **General**: Tolerations may need adjustment for provider-specific node taints
  (e.g., `eks.amazonaws.com/compute-type` on EKS Fargate profiles). Falcosidekick
  integration and custom rules remain identical across providers.

## Certification Relevance

| Certification | Relevance                                                              |
|---------------|------------------------------------------------------------------------|
| **CKS**       | Runtime security is ~20% of the CKS exam. Falco is the primary tool for syscall-based threat detection, rule writing, and incident response. |
| **KCSA**      | Covers runtime security concepts and the role of eBPF-based monitoring in Kubernetes security architecture. |
| **CKA/CKAD**  | Not directly tested, but understanding DaemonSets, tolerations, and resource management applies. |

## Learn More

- [Falco documentation](https://falco.org/docs/)
- [CNCF project page](https://www.cncf.io/projects/falco/)
- [GitHub repository](https://github.com/falcosecurity/falco)
- [Falco rules reference](https://falco.org/docs/reference/rules/)
- [Falcosidekick outputs](https://github.com/falcosecurity/falcosidekick)
- [Helm chart repository](https://github.com/falcosecurity/charts)
