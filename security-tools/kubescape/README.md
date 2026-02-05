# Kubescape Configuration

Kubescape is a CNCF Incubating project for Kubernetes security posture management
and compliance scanning.

## Installation

```bash
helm repo add kubescape https://kubescape.github.io/helm-charts/
helm repo update

helm install kubescape kubescape/kubescape-operator \
  --namespace kubescape \
  --create-namespace \
  -f values.yaml
```

## Running Compliance Scans

```bash
# Run NSA hardening scan
kubescape scan framework nsa --enable-host-scan

# Run SOC2 compliance scan
kubescape scan framework soc2

# Run MITRE ATT&CK scan
kubescape scan framework mitre

# Run all frameworks
kubescape scan framework all

# Scan specific namespace
kubescape scan framework nsa --include-namespaces vulnerable-app,compliant-app
```

## Viewing Results

```bash
# View scan results in cluster
kubectl get workloadconfigurationscans -A

# Export results as PDF for compliance evidence
kubescape scan framework nsa --format pdf --output compliance-report.pdf
```

## Scheduled Scans

See `scheduled-scans/daily-compliance-scan.yaml` for automated daily scanning.
