# Trivy Operator Configuration

Trivy is a comprehensive security scanner for containers and Kubernetes.
The Trivy Operator runs continuous scanning within the cluster.

## Installation

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update

helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  -f values.yaml
```

## Viewing Scan Results

```bash
# View vulnerability reports
kubectl get vulnerabilityreports -A

# View SBOM reports
kubectl get sbomreports -A

# View detailed report for a workload
kubectl get vulnerabilityreport -n <namespace> <report-name> -o yaml
```

## SBOM Generation

SBOM (Software Bill of Materials) generation is enabled by default.
Reports are stored as Kubernetes custom resources and can be exported
for regulatory compliance evidence.
