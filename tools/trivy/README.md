# Trivy Operator

> **CNCF Status:** Community (Aqua Security)
> **Category:** Vulnerability Scanner
> **Difficulty:** Beginner
> **AKS Compatibility:** Supported

## What It Does

Trivy Operator runs continuous vulnerability scanning as a Kubernetes operator. It watches for new
pods and workloads, automatically scans their container images for CVEs, generates Software Bill of
Materials (SBOM), and detects misconfigurations. Scan results are stored as Kubernetes Custom
Resources (VulnerabilityReport, SBOMReport, ConfigAuditReport) that can be queried with kubectl.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Vulnerability management program (Part 748, Appendix B) |
| SOC 2 | CC7.1 - Detection and monitoring of security events |
| DORA | Article 9 - Vulnerability assessment processes; Article 28 - SBOM for supply chain |
| PCI-DSS | 6.1 - Establish a process to identify security vulnerabilities |

## Architecture

Trivy Operator runs as a **Deployment** (controller/operator pattern) in the `trivy-system`
namespace. When new workloads are created or updated, the operator:

1. Detects the change via Kubernetes watch events
2. Creates short-lived scan Jobs that pull and analyze container images
3. Stores results as Custom Resources alongside the scanned workloads

```
+------------------+     Watch      +------------------+
| Trivy Operator   | <------------ | Workloads        |
| (Controller)     |               | (Deployments,    |
+--------+---------+               | DaemonSets...)   |
         |                         +------------------+
         | Creates scan Jobs
         v
+------------------+     Scans     +------------------+
| Scan Jobs        | ------------> | Container Images |
| (Trivy Scanner)  |              | (OCI Registry)   |
+--------+---------+              +------------------+
         |
         | Creates reports
         v
+------------------+
| Custom Resources |
| - VulnReport     |
| - ConfigAudit    |
| - SBOMReport     |
+------------------+
```

## Quick Start (AKS)

### Prerequisites
- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured

### Install

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update

helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  -f values.yaml
```

### Verify

```bash
# Check operator pod is running
kubectl get pods -n trivy-system

# Wait for initial scans, then view vulnerability reports
kubectl get vulnerabilityreports -A

# View SBOM reports
kubectl get sbomreports -A

# View detailed report for a specific workload
kubectl get vulnerabilityreport -n <namespace> <report-name> -o yaml
```

## Key Configuration Decisions

See [values.yaml](./values.yaml) for the full configuration.

- **Scan on deploy**: The operator watches for workload changes and scans automatically; no manual triggers needed.
- **All severity levels reported**: `severity: UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL` captures the complete risk picture for auditors. Alert thresholds are handled downstream by Kyverno policies.
- **SBOM generation enabled**: `sbomGeneration.enabled: true` satisfies supply chain transparency requirements (DORA Article 28, US Executive Order 14028).
- **Unfixed CVEs shown**: `ignoreUnfixed: false` ensures auditors see the full vulnerability posture, including residual risk from unpatched CVEs.
- **Config audit enabled**: `configAuditScannerEnabled: true` validates Kubernetes resource configurations against security best practices.
- **CIS and NSA compliance**: `compliance.specs` includes `k8s-cis-1.10` and `k8s-nsa-1.0` for automated benchmark evaluation.
- **10 concurrent scan jobs**: Balances scan throughput against cluster resource consumption for medium-sized clusters.

## EKS / GKE Notes

- **EKS**: No changes required. ECR image scanning is complementary (registry-level vs runtime-level). Ensure IRSA is configured if pulling from private ECR repositories.
- **GKE**: No changes required. Artifact Registry vulnerability scanning is complementary. GKE Autopilot clusters may restrict scan Job scheduling; use Standard mode.
- **Registry rate limits**: DockerHub and other registries may throttle pull requests. Adjust `concurrentScanJobsLimit` if you see rate-limit errors.

## Certification Relevance

- **CKS (Certified Kubernetes Security Specialist)**: Supply chain security domain (~20%) covers image scanning, SBOM, and vulnerability management -- core Trivy Operator capabilities.
- **KCSA (Kubernetes and Cloud Native Security Associate)**: Vulnerability scanning and compliance reporting are key exam topics.

## Learn More

- [Official docs](https://aquasecurity.github.io/trivy-operator/)
- [GitHub repository](https://github.com/aquasecurity/trivy-operator)
- [Trivy scanner docs](https://aquasecurity.github.io/trivy/)
