# Prometheus (kube-prometheus-stack)

> **CNCF Status:** Graduated
> **Category:** Observability / Metrics
> **Difficulty:** Intermediate
> **AKS Compatibility:** Supported

## What It Does

Prometheus is a time-series metrics collection and alerting system that serves as the
foundation of Kubernetes observability. The kube-prometheus-stack Helm chart bundles
Prometheus, Alertmanager, Grafana, node-exporter, and kube-state-metrics into a single
deployment, providing full cluster observability from infrastructure metrics to application
performance. It scrapes metrics endpoints at configurable intervals, stores them in a
local time-series database, evaluates alerting rules, and routes notifications through
Alertmanager.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Incident detection through anomaly alerting, capacity monitoring for service resilience, audit trail of system health over time |
| SOC 2 | CC7.2 System monitoring and anomaly detection, CC7.3 Incident detection and response triggers |
| DORA | Article 10 Detection of anomalous activities in ICT systems, Article 11 Capacity management and performance monitoring |
| PCI-DSS | Requirement 10.6 Review of audit logs and security events, Requirement 10.7 Retention of monitoring data |

## Architecture

Prometheus operates on a pull-based model. The server scrapes metrics from configured
targets at regular intervals, stores them locally, evaluates alerting rules, and forwards
firing alerts to Alertmanager for notification routing.

```
                        kube-prometheus-stack
+-----------------------------------------------------------------------+
|                                                                       |
|  +------------------+         +-----------------+                     |
|  | Prometheus       |-------->| Alertmanager    |---> Slack/Email/    |
|  | Server           |  fires  | (2 replicas)    |     PagerDuty/     |
|  | (scrapes targets |  alerts |                 |     OpsGenie        |
|  |  every 30s)      |         +-----------------+                     |
|  +--------+---------+                                                 |
|           |                                                           |
|           | scrapes /metrics                                          |
|           |                                                           |
|  +--------+--------+--------+--------+--------+                      |
|  |        |        |        |        |        |                      |
|  v        v        v        v        v        v                      |
| node-  kube-    kubelet  Falco   Kyverno  App                       |
| export state-   cAdvisor                  endpoints                  |
| er     metrics                                                       |
|                                                                       |
|  +------------------+                                                 |
|  | Grafana          |<--- Queries PromQL from Prometheus              |
|  | (Dashboards)     |     Preconfigured dashboards for:              |
|  |                  |       - Cluster health                         |
|  |                  |       - Node resources                         |
|  |                  |       - Pod/container metrics                   |
|  |                  |       - Security tool status                    |
|  +------------------+                                                 |
+-----------------------------------------------------------------------+
```

- **Prometheus Server** -- Scrapes metrics from all configured targets via HTTP
  `/metrics` endpoints. Stores time-series data locally with configurable retention.
  Evaluates `PrometheusRule` CRDs to determine when alerts should fire.
- **Alertmanager** -- Receives firing alerts from Prometheus, deduplicates them,
  groups related alerts, silences acknowledged issues, and routes notifications to
  the appropriate channel (Slack, email, PagerDuty, webhooks).
- **Grafana** -- Visualization layer that queries Prometheus using PromQL. Ships
  with preconfigured dashboards for cluster health, node resources, and Kubernetes
  workload metrics. Custom dashboards can map security metrics to regulatory controls.
- **node-exporter** -- DaemonSet that exposes hardware and OS-level metrics from
  each node (CPU, memory, disk, network). Essential for capacity monitoring.
- **kube-state-metrics** -- Listens to the Kubernetes API server and generates
  metrics about the state of objects (deployments, pods, nodes, etc.).

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured

### Install

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f values.yaml
```

### Verify

```bash
# Confirm all pods are running in the monitoring namespace
kubectl get pods -n monitoring

# Check Prometheus targets are being scraped
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets in your browser

# Check Alertmanager is reachable
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# Visit http://localhost:9093 in your browser

# Access Grafana dashboards
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Visit http://localhost:3000 (default: admin / prom-operator)

# List active PrometheusRule resources
kubectl get prometheusrule -A

# Run a quick PromQL query to verify metrics are flowing
kubectl exec -n monitoring svc/kube-prometheus-stack-prometheus -- \
  promtool query instant http://localhost:9090 'up'
```

## Key Configuration Decisions

Configuration is in [`values.yaml`](./values.yaml). Key settings:

- **Retention period: 72h** -- For a lab or demo, 72 hours of metric history is
  sufficient to observe trends without consuming excessive storage. Production
  environments typically retain 15-30 days locally, with long-term storage offloaded
  to Thanos or Cortex for regulatory retention requirements.
- **Scrape interval: 30s** -- The default 30-second interval balances metric resolution
  against resource consumption. For security-critical metrics (e.g., Falco event rates),
  consider a 15s interval via per-target ServiceMonitor overrides.
- **Storage: 10Gi PersistentVolumeClaim** -- Sized for the 72h retention window on a
  small cluster. Production sizing follows the formula:
  `storage = retention_seconds * ingested_samples_per_second * bytes_per_sample`.
  Typically 2 bytes/sample, so 100k samples/s for 15 days requires ~250Gi.
- **Alertmanager: enabled, unconfigured receivers** -- Alertmanager is deployed but
  notification receivers (Slack, email, PagerDuty) are commented out in values.yaml.
  Uncomment and configure for your environment.
- **Grafana: enabled with default dashboards** -- The sidecar automatically loads
  dashboards from ConfigMaps. Default kube-prometheus-stack dashboards cover cluster
  health, node metrics, and workload performance.
- **AKS managed components: disabled** -- kube-proxy, etcd, kube-scheduler, and
  kube-controller-manager scraping is disabled because AKS manages the control plane
  and does not expose these metrics endpoints. Attempting to scrape them results in
  persistent target-down alerts.
- **Resource sizing: lab-appropriate** -- Prometheus requests 500m CPU / 1Gi memory,
  which is appropriate for a small cluster. Production deployments on clusters with
  hundreds of nodes should allocate 2-4 CPU cores and 8-16Gi memory.
- **ServiceMonitor: enabled** -- When kube-prometheus-stack is installed, ServiceMonitor
  CRDs are available cluster-wide. Other tools (Falco, Kyverno, Trivy) can set
  `serviceMonitor.enabled: true` in their own Helm values to be scraped automatically.

## Alerting Rules

Prometheus uses `PrometheusRule` Custom Resource Definitions (CRDs) to define alerting
and recording rules. The kube-prometheus-stack ships with a comprehensive set of default
rules covering node health, pod restarts, and Kubernetes component failures.

### How PrometheusRule CRDs Work

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: example-alerts
  labels:
    release: kube-prometheus-stack  # Must match Prometheus ruleSelector
spec:
  groups:
    - name: example
      rules:
        - alert: HighPodRestartCount
          expr: increase(kube_pod_container_status_restarts_total[1h]) > 5
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ $labels.pod }} restarting frequently"
```

Key points:
- The `release` label must match the Prometheus `ruleSelector` (set in values.yaml)
  for the rule to be picked up.
- `expr` is a PromQL expression that evaluates to true when the alert should fire.
- `for` specifies how long the expression must be true before the alert fires,
  preventing transient spikes from triggering notifications.
- Custom security-focused alerting rules are in the [`alert-rules/`](./alert-rules/)
  directory.

## EKS / GKE Notes

The kube-prometheus-stack Helm chart works on any conformant Kubernetes distribution.
However, all three major cloud providers offer managed Prometheus alternatives:

| Provider | Managed Service | Self-Hosted Compatible? |
|----------|----------------|------------------------|
| **GKE** | Google Cloud Managed Service for Prometheus (GMP) -- fully managed, uses same PromQL, integrates with Cloud Monitoring | Yes, self-hosted kube-prometheus-stack works identically |
| **EKS** | Amazon Managed Service for Prometheus (AMP) -- managed Prometheus-compatible service, uses remote_write for ingestion | Yes, self-hosted kube-prometheus-stack works identically |
| **AKS** | Azure Monitor managed service for Prometheus -- integrates with Azure Monitor and Grafana | Yes, self-hosted kube-prometheus-stack works identically |

**Recommendation for regulated environments:** Self-hosted kube-prometheus-stack
provides full control over data residency, retention, and access -- critical for
regulatory compliance. Managed services simplify operations but may introduce
data sovereignty concerns depending on your regulatory framework.

**Cloud-specific considerations:**
- **EKS:** etcd, scheduler, and controller-manager are also not scrapeable (same as AKS).
  Disable the same components in values.yaml.
- **GKE:** Same control plane limitations. GKE Autopilot clusters may have additional
  restrictions on DaemonSets (node-exporter) -- verify tolerations.
- **All providers:** node-exporter, kube-state-metrics, kubelet/cAdvisor, and application
  ServiceMonitors work identically across all providers.

## Certification Relevance

| Certification | Relevance |
|--------------|-----------|
| **CKA** (Certified Kubernetes Administrator) | Cluster monitoring and logging, understanding metrics pipelines, troubleshooting with metrics |
| **CKS** (Certified Kubernetes Security Specialist) | Audit and monitoring, detecting anomalous behavior, security event alerting |
| **KCNA** (Kubernetes and Cloud Native Associate) | Observability concepts, understanding the role of Prometheus in the CNCF ecosystem |
| **KCSA** (Kubernetes and Cloud Native Security Associate) | Security monitoring, incident detection, understanding metrics-based security alerting |

## Learn More

- [Prometheus Documentation](https://prometheus.io/docs/)
- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [CNCF Project Page](https://www.cncf.io/projects/prometheus/)
- [Prometheus GitHub Repository](https://github.com/prometheus/prometheus)
- [PromQL Documentation](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Grafana Dashboards for Kubernetes](https://grafana.com/grafana/dashboards/?search=kubernetes)
- [Awesome Prometheus Alerts](https://samber.github.io/awesome-prometheus-alerts/) -- community-curated alerting rules
