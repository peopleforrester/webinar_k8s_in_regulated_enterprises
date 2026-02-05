# Compliant Application

This is a hardened nginx deployment that passes all Kyverno policies.
Use this as a reference for production-ready container configurations.

## Security Controls

| Control | Kyverno Policy | Implementation |
|---------|---------------|----------------|
| Non-privileged | disallow-privileged-containers | privileged: false |
| Non-root user | require-run-as-nonroot | runAsNonRoot: true, runAsUser: 101 |
| Explicit tag | disallow-latest-tag | nginx:1.25.4 |
| Resource limits | require-resource-limits | CPU/memory limits set |
| Read-only rootfs | require-readonly-rootfs | readOnlyRootFilesystem: true |
| Network policy | N/A | Restrictive ingress/egress rules |
| Minimal SA | N/A | automountServiceAccountToken: false |

## Deployment

```bash
# Deploy after Kyverno policies are applied
kubectl apply -f namespace.yaml
kubectl apply -f .
# Expected: all resources created successfully
```
