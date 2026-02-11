# Grafana

> **CNCF Status:** Community (Grafana Labs)
> **Category:** Observability / Visualization
> **Difficulty:** Beginner
> **AKS Compatibility:** Supported
>
> **Deployment:** Grafana is deployed as a subchart of `kube-prometheus-stack`
> (Tier 2 install). The `values.yaml` in this directory is for standalone
> reference. The `dashboards/` directory contains ConfigMaps applied by the
> install script after Prometheus Stack deployment.

## What It Does

Grafana is an open-source dashboarding and visualization platform that queries
time-series data sources such as Prometheus and Loki to render interactive graphs,
tables, and alerts. It is commonly deployed as part of the kube-prometheus-stack
Helm chart alongside Prometheus and Alertmanager. In regulated environments, Grafana
provides the visual evidence layer that turns raw metrics into auditor-friendly
compliance dashboards.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Security monitoring dashboards, audit evidence visualization, incident response visibility |
| SOC 2 | CC7.2 Monitoring controls evidence -- dashboards demonstrate continuous monitoring capability |
| DORA | Article 10 anomaly detection visualization, Article 13 ICT incident reporting dashboards |
| PCI-DSS | Requirement 10.6 log review dashboards, audit trail visualization, security event monitoring |

## Architecture

Grafana is typically deployed alongside Prometheus and Loki, with dashboards
provisioned automatically via Kubernetes ConfigMaps using the sidecar pattern:

```
+-------------------+       +-----------------------+
| Grafana Pod       |       | Data Sources          |
|                   |       |                       |
| +---------------+ |  QL   | +-------------------+ |
| | Grafana       +-------->| | Prometheus        | |
| | Server        | |       | | (metrics)         | |
| +---------------+ |       | +-------------------+ |
| +---------------+ |  QL   | +-------------------+ |
| | Sidecar       | |       | | Loki              | |
| | (dashboard    +-------->| | (logs)            | |
| |  provisioner) | |       | +-------------------+ |
| +-------+-------+ |       +-----------------------+
|         |         |
+---------+---------+
          |
          | watches
          v
+-------------------+
| ConfigMaps with   |
| label:            |
| grafana_dashboard |
| = "1"             |
+-------------------+
```

- **Grafana Server** -- Serves the web UI on port 3000. Queries data sources using
  PromQL, LogQL, or other query languages. Renders dashboards and evaluates alert rules.
- **Sidecar Container** -- Watches for ConfigMaps with the label `grafana_dashboard: "1"`
  across all namespaces. When a matching ConfigMap is created or updated, the sidecar
  copies its content into the Grafana dashboard provisioning directory.
- **Data Sources** -- Prometheus provides metrics (PromQL), Loki provides logs (LogQL).
  Additional sources like Tempo (traces) or PostgreSQL (audit logs) can be configured.

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured

### Recommended: Deploy with kube-prometheus-stack

Grafana is typically deployed as part of the kube-prometheus-stack Helm chart, which
bundles Prometheus, Alertmanager, Grafana, and a curated set of dashboards and alert
rules. See [tools/prometheus/](../prometheus/) for the full-stack installation.

### Standalone Install

If you need Grafana independently (for example, pointing at an existing Prometheus):

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install grafana grafana/grafana \
  --namespace monitoring \
  --create-namespace \
  -f values.yaml
```

### Apply Dashboard ConfigMaps

```bash
kubectl apply -f dashboards/ -n monitoring
```

### Access the UI

```bash
# Port-forward to access Grafana locally
kubectl port-forward svc/grafana 3000:80 -n monitoring

# Open http://localhost:3000 in your browser
# Default credentials: admin / (see kubectl get secret)
kubectl get secret grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d
```

### Verify

```bash
# Confirm Grafana pod is running
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Check that dashboards were provisioned
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard
```

## Dashboards in This Repo

The [`dashboards/`](./dashboards/) directory contains Kubernetes ConfigMaps with
embedded Grafana dashboard JSON. These are automatically provisioned by the Grafana
sidecar container when deployed with the values in this directory.

| Dashboard | File | Purpose |
|-----------|------|---------|
| Cluster Overview | `cluster-overview.yaml` | Node CPU/memory, pod counts, restarts, network I/O |
| Security Posture | `security-posture.yaml` | Kyverno violations, Falco alerts, Trivy vulnerabilities |

Each ConfigMap carries the label `grafana_dashboard: "1"` so the sidecar picks it up
automatically. No manual import is required.

## Key Configuration Decisions

Configuration is in [`values.yaml`](./values.yaml). Key settings:

- **Dashboard provisioning: sidecar pattern** -- Dashboards are stored as ConfigMaps
  in Kubernetes and auto-loaded by a sidecar container. This is the recommended
  GitOps-compatible approach. Alternatives include the Grafana HTTP API (imperative)
  or Terraform provider (good for multi-instance setups).
- **Persistence: enabled (1Gi)** -- Dashboard changes made via the UI are preserved
  across pod restarts. In production, treat the UI as read-only and manage dashboards
  exclusively through ConfigMaps for auditability.
- **Authentication: basic auth enabled, anonymous disabled** -- For regulated
  environments, configure OIDC/SSO integration with Azure AD or your identity provider.
  An example OIDC configuration is included (commented out) in `values.yaml`.
- **Folder organization** -- Dashboards can be organized into folders by setting
  `grafana_dashboard_folder` annotations on ConfigMaps. Use folders to separate
  infrastructure, security, and application dashboards.
- **Alerting: use Alertmanager** -- Grafana has built-in alerting, but in a
  kube-prometheus-stack deployment, Alertmanager is the canonical alert routing engine.
  Configure Grafana alert rules only for dashboard-specific thresholds.
- **Service type: ClusterIP** -- Access via port-forward or Ingress. Do not expose
  Grafana directly to the internet without authentication and TLS.

## EKS / GKE Notes

Grafana works identically on EKS, GKE, and any conformant Kubernetes distribution.
The Helm chart, dashboard ConfigMaps, and data source configuration apply without
modification. On AKS specifically, Azure Managed Grafana is available as a fully
managed alternative that integrates with Azure Monitor and Azure AD -- consider it
for teams that prefer a managed service over self-hosted Grafana.

## Certification Relevance

| Certification | Relevance |
|--------------|-----------|
| **CKA** (Certified Kubernetes Administrator) | Cluster monitoring, resource usage visibility, troubleshooting with dashboards |
| **KCNA** (Kubernetes and Cloud Native Associate) | Observability concepts, understanding metrics and visualization in cloud-native stacks |

## Learn More

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [GitHub Repository](https://github.com/grafana/grafana)
- [Grafana Dashboard Marketplace](https://grafana.com/grafana/dashboards/)
- [Grafana Labs Blog](https://grafana.com/blog/)
- [Helm Chart (grafana/grafana)](https://github.com/grafana/helm-charts/tree/main/charts/grafana)
- [kube-prometheus-stack Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
