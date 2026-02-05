# Falco Configuration

Falco is a CNCF Graduated project for runtime threat detection in Kubernetes.

## Installation

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

# Install with custom values
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  -f values.yaml
```

## Custom Rules

Financial services-specific rules are in `custom-rules/financial-services.yaml`.

## Viewing Alerts

```bash
# Stream Falco logs
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# View alerts in Falcosidekick UI (if enabled)
kubectl port-forward -n falco svc/falcosidekick-ui 2802:2802
```
