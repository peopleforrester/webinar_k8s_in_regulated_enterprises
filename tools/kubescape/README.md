# Kubescape

> **CNCF Status:** Incubating
> **Category:** Compliance Scanner
> **Difficulty:** Beginner
> **AKS Compatibility:** Supported

## What It Does

Kubescape scans Kubernetes clusters against industry-standard security frameworks including NSA
Kubernetes Hardening Guide, CIS Benchmarks, SOC 2, and MITRE ATT&CK. It provides compliance scores,
identifies misconfigurations, detects vulnerabilities, and generates actionable remediation guidance.
The operator runs scheduled scans continuously, while the CLI supports on-demand assessments.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Risk assessment of information systems (Part 748); CIS benchmark references |
| SOC 2 | CC6.1 - Security control testing; CC7.1 - Monitoring |
| DORA | Article 5 - ICT risk management framework; Article 9 - Network segmentation |
| PCI-DSS | 6.5 - Develop applications securely; 2.2 - Configuration standards |

## Architecture

Kubescape deploys as an **Operator** with several components in the `kubescape` namespace:

- **Operator**: Long-running controller that schedules and orchestrates scans
- **Scanner**: On-demand pods launched for cluster-wide assessments
- **Node Agent**: DaemonSet with eBPF-based runtime observability on every node
- **Storage**: Local persistence for scan results and compliance evidence

```
+-------------+    +-------------+    +-------------+    +-------------+
| Operator    |    | Scanner     |    | Node Agent  |    | Storage     |
| (Control)   |--->| (On-demand) |    | (eBPF)      |    | (Results)   |
+-------------+    +-------------+    +-------------+    +-------------+
                         |                  |                   ^
                         v                  v                   |
                   Cluster Resources   Process/Network     Scan Results
                   Configuration       Behavior            (Local/Cloud)
```

## Quick Start (AKS)

### Prerequisites
- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured

### Install

```bash
helm repo add kubescape https://kubescape.github.io/helm-charts/
helm repo update

helm install kubescape kubescape/kubescape-operator \
  --namespace kubescape \
  --create-namespace \
  -f values.yaml
```

### Verify

```bash
# Check all Kubescape pods are running
kubectl get pods -n kubescape

# View scan results stored in-cluster
kubectl get workloadconfigurationscans -A

# Run an on-demand NSA framework scan via CLI
kubescape scan framework nsa --enable-host-scan

# Run SOC 2 compliance scan
kubescape scan framework soc2

# Run MITRE ATT&CK framework scan
kubescape scan framework mitre

# Scan specific namespaces
kubescape scan framework nsa --include-namespaces vulnerable-app,compliant-app

# Export results as PDF for compliance evidence
kubescape scan framework nsa --format pdf --output compliance-report.pdf
```

## Key Configuration Decisions

See [values.yaml](./values.yaml) for the full configuration.

- **Framework selection**: `NSA`, `MITRE`, `SOC2`, and `CIS-v1.12.0` frameworks are all enabled -- covering the major compliance requirements for financial services.
- **Scheduled scans**: `schedule: "0 2 * * *"` runs daily at 2:00 AM to satisfy "continuous monitoring" requirements without impacting daytime workloads.
- **Severity threshold**: `severityThreshold: medium` captures significant issues while avoiding alert fatigue from low-severity findings.
- **All capabilities enabled**: Continuous scan, vulnerability scan, configuration scan, node scan, network policy analysis, and runtime observability are all active for comprehensive coverage.
- **Local storage**: `storage.enabled: true` with 90-day retention ensures scan evidence is retained in-cluster for audit purposes, independent of any external vendor.
- **Runtime observability**: eBPF-based monitoring complements Falco by detecting anomalies from learned behavioral baselines (vs Falco's rule-based detection).

## EKS / GKE Notes

- **EKS**: No changes required. Node Agent eBPF works on Amazon Linux 2 and Bottlerocket. Ensure IAM roles are configured for any ECR image scanning.
- **GKE**: Standard mode works without changes. GKE Autopilot restricts DaemonSets and eBPF -- disable `nodeScan` and `runtimeObservability` capabilities, or use Standard mode.
- **eBPF kernel requirement**: Node Agent requires Linux kernel 4.14+ for eBPF support. All major managed Kubernetes offerings meet this requirement.

## Certification Relevance

- **CKS (Certified Kubernetes Security Specialist)**: System hardening domain (~15%) covers CIS benchmarks, security configurations, and compliance scanning that Kubescape directly addresses.
- **KCSA (Kubernetes and Cloud Native Security Associate)**: Compliance frameworks, security posture management, and vulnerability scanning are core exam topics.

## Learn More

- [Official docs](https://kubescape.io/docs/)
- [CNCF project page](https://www.cncf.io/projects/kubescape/)
- [GitHub repository](https://github.com/kubescape/kubescape)
