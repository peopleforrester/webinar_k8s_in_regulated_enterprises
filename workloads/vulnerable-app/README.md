# Vulnerable Application

This is an intentionally insecure nginx deployment used to demonstrate
security tool detection capabilities. **Do not use this in production.**

## Security Violations

This application intentionally violates the following policies:

| Violation | Kyverno Policy | Description |
|-----------|---------------|-------------|
| Privileged container | disallow-privileged-containers | Runs with privileged: true |
| Root user | require-run-as-nonroot | No runAsNonRoot set |
| Latest tag | disallow-latest-tag | Uses nginx:latest |
| No resource limits | require-resource-limits | Missing CPU/memory limits |
| No image digest | require-image-digest | No SHA256 digest |
| Writable rootfs | require-readonly-rootfs | No readOnlyRootFilesystem |
| Overpermissioned SA | N/A | ClusterRole with secrets access |

## Deployment

```bash
# Deploy BEFORE applying Kyverno policies
kubectl apply -f namespace.yaml
kubectl apply -f .

# After Kyverno policies are applied, redeployment should FAIL
kubectl delete -f deployment.yaml
kubectl apply -f deployment.yaml
# Expected: blocked by Kyverno
```
