# Kyverno Policies

Kyverno is a CNCF Incubating policy engine designed for Kubernetes.

## Installation

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# Install Kyverno
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  -f values.yaml

# Apply policies
kubectl apply -k policies/
```

## Policies Included

| Policy | Description | Mode |
|--------|-------------|------|
| disallow-privileged-containers | Block privileged containers | Enforce |
| require-run-as-nonroot | Require non-root user | Enforce |
| disallow-latest-tag | Block :latest image tag | Enforce |
| require-resource-limits | Require CPU/memory limits | Enforce |
| require-image-digest | Require image SHA digest | Audit |
| require-readonly-rootfs | Require read-only root filesystem | Audit |

## Testing Policies

```bash
# Test with Kyverno CLI
kyverno apply policies/ --resource ../../workloads/vulnerable-app/deployment.yaml

# Check policy reports
kubectl get polr -A
```
