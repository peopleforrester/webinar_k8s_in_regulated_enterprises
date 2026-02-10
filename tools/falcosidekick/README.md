# Falcosidekick

> **CNCF Status:** Sandbox
> **Category:** Alert Routing
> **Difficulty:** Beginner
> **AKS Compatibility:** Supported

## What It Does

Falcosidekick receives security alerts from Falco and routes them to 50+ destinations including Slack, Microsoft Teams, SIEM platforms (Splunk, Elasticsearch, Azure Sentinel), PagerDuty, and custom webhooks. It decouples Falco from its alert destinations, adds metadata enrichment with Kubernetes context, and supports priority-based filtering so different teams and systems receive the alerts relevant to them.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Part 748 - Incident notification, timely escalation of security events to appropriate personnel |
| SOC 2 | CC7.3 - Incident communication, ensuring security events reach stakeholders |
| DORA | Art 19 - ICT-related incident reporting and notification to management |

## Architecture

Falcosidekick runs as a Deployment in the `falco` namespace. Falco sends events to Falcosidekick via HTTP/gRPC webhook. Falcosidekick then fans out each alert to all configured output destinations simultaneously.

```
+--------+   HTTP/gRPC   +---------------+   Fan-out   +------------+
| Falco  | ------------> | Falcosidekick | --------+-> | Slack      |
+--------+               +-------+-------+         +-> | SIEM       |
                                 |                  +-> | Webhook    |
                                 v                  +-> | PagerDuty  |
                         +---------------+          +-> | Event Hub  |
                         | Sidekick UI   |
                         | (port 2802)   |
                         +---------------+
```

## Quick Start (AKS)

### Prerequisites
- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured

### Install

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falcosidekick falcosecurity/falcosidekick \
  --namespace falco \
  -f values.yaml
```

### Verify

```bash
# Check pod status
kubectl get pods -n falco -l app.kubernetes.io/name=falcosidekick

# Verify the web UI is accessible
kubectl port-forward -n falco svc/falcosidekick-ui 2802:2802
# Open http://localhost:2802
```

## Key Configuration Decisions

See [`values.yaml`](./values.yaml) in this directory for the full configuration.

- **Web UI enabled** (`webui.enabled: true`) -- provides real-time alert visualization for demos and SOC secondary displays. Redis persistence is disabled (ephemeral mode) since this is a demo environment.
- **Output destinations** -- Slack, Azure Event Hub, Elasticsearch, and generic webhook outputs are defined. Webhook URLs and connection strings are left empty and should be injected via Kubernetes Secrets, never committed to git.
- **Priority filtering** (`minimumpriority: "warning"`) -- reduces noise by only forwarding warning-level and above alerts to most outputs.
- **Custom fields** (`environment:demo,cluster:aks-regulated-demo`) -- added to every alert for downstream filtering and incident attribution.
- **ServiceMonitor enabled** -- exposes Prometheus metrics (`falcosidekick_inputs_total`, `falcosidekick_outputs_total`, `falcosidekick_outputs_errors`) for monitoring alert delivery health.
- **Resource limits** -- lightweight (50m/64Mi requests, 200m/128Mi limits) since Falcosidekick is an I/O-bound event router.

## EKS / GKE Notes

No significant differences. Falcosidekick is a standard Kubernetes Deployment that works identically across AKS, EKS, and GKE. The only cloud-specific concern is the output destination: swap Azure Event Hub for AWS SNS/SQS on EKS or GCP Pub/Sub on GKE.

## Certification Relevance

- **CKS** (Certified Kubernetes Security Specialist) -- monitoring and alerting for runtime security events, integrating detection tools with notification systems.
- **KCSA** (Kubernetes and Cloud Native Security Associate) -- understanding security observability and incident notification pipelines in cloud-native environments.

## Learn More

- [Official documentation](https://github.com/falcosecurity/falcosidekick/blob/master/docs/outputs)
- [CNCF project page](https://www.cncf.io/projects/falcosidekick/)
- [GitHub repository](https://github.com/falcosecurity/falcosidekick)
- [Supported outputs list](https://github.com/falcosecurity/falcosidekick#outputs)
