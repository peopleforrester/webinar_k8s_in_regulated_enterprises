# Falcosidekick Configuration

Falcosidekick connects Falco output to various notification channels and SIEM systems.

## Installation

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falcosidekick falcosecurity/falcosidekick \
  --namespace falco \
  -f values.yaml
```

## Accessing the UI

```bash
kubectl port-forward -n falco svc/falcosidekick-ui 2802:2802
# Open http://localhost:2802
```

## Supported Outputs

Falcosidekick can forward alerts to:
- Slack, Teams, Discord
- Azure Event Hub, Log Analytics
- Elasticsearch, Splunk
- PagerDuty, OpsGenie
- Custom webhooks
