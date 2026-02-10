# Helm

> **CNCF Status:** Graduated
> **Category:** Package Manager
> **Difficulty:** Beginner
> **AKS Compatibility:** Native

## What It Does

Helm is the package manager for Kubernetes. It packages related Kubernetes manifests
into reusable **charts**, applies user-supplied **values** to template them, and tracks
each installation as a versioned **release** stored in the cluster. Helm enables
one-command installs, upgrades, and rollbacks -- giving teams reproducible deployments
with a built-in audit trail of every change.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Change management -- every release is versioned and reversible; audit trail of deployments |
| SOC 2 | CC8.1 Change management -- Helm releases provide evidence of what was deployed, when, and by whom |
| DORA | Article 9 ICT configuration management -- charts codify infrastructure-as-code with version-controlled values |
| PCI-DSS | Requirement 6.5 Change control procedures -- Helm enforces versioned, reviewable deployment artifacts |

## Architecture

Helm is a client-side CLI that communicates directly with the Kubernetes API server.
There is no server-side component (Tiller was removed in Helm 3).

```
+-----------+        +------------------+        +-------------------+
| Helm CLI  | -----> | Kubernetes       | -----> | Release stored    |
| (client)  |  API   | API Server       |        | as K8s Secret     |
+-----------+        +------------------+        | (in release ns)   |
                                                  +-------------------+

Chart Structure:
+----------------------------+
| my-chart/                  |
|   Chart.yaml               |  <- metadata (name, version, dependencies)
|   values.yaml              |  <- default configuration values
|   templates/               |  <- Go-templated Kubernetes manifests
|     deployment.yaml        |
|     service.yaml           |
|     _helpers.tpl           |  <- reusable template snippets
+----------------------------+

Release Lifecycle:
  helm install  -->  Release v1 (Secret: sh.helm.release.v1.<name>.v1)
  helm upgrade  -->  Release v2 (Secret: sh.helm.release.v1.<name>.v2)
  helm rollback -->  Release v3 (reverts to v1 config, stored as new revision)
```

- **Charts** -- A directory of templated YAML files with metadata. Charts can declare
  dependencies on other charts and be published to registries (OCI or HTTP).
- **Values** -- User-supplied configuration that overrides chart defaults. Values flow
  into templates via Go template syntax (`{{ .Values.image.tag }}`).
- **Releases** -- Each `helm install` or `helm upgrade` creates a numbered release
  revision stored as a Kubernetes Secret in the release namespace. This provides a
  complete audit trail and enables instant rollback.

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- kubectl configured (`az aks get-credentials --admin`)

### Install Helm

Helm is a client-side tool. Install it on your workstation:

```bash
# macOS
brew install helm

# Linux (official install script)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

### Add a Chart Repository

```bash
# Add the Bitnami chart repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Search for available charts
helm search repo bitnami/nginx
```

### Install a Chart

```bash
# Install nginx with custom values
helm install my-nginx bitnami/nginx \
  --namespace demo \
  --create-namespace \
  --set service.type=ClusterIP \
  --wait
```

### List Releases

```bash
# List all releases across all namespaces
helm list -A

# Show release history (revision log)
helm history my-nginx -n demo
```

### Upgrade a Release

```bash
# Upgrade with new values
helm upgrade my-nginx bitnami/nginx \
  --namespace demo \
  --set replicaCount=3 \
  --wait
```

### Rollback a Release

```bash
# Roll back to the previous revision
helm rollback my-nginx 1 -n demo

# Verify the rollback
helm history my-nginx -n demo
```

### Uninstall a Release

```bash
# Remove the release and all its resources
helm uninstall my-nginx -n demo
```

## Key Configuration Decisions

### OCI Registry Support

Helm 3.8+ supports OCI registries natively. Instead of HTTP chart repositories, you can
push and pull charts from container registries like ACR, ECR, or GHCR:

```bash
# Push a chart to Azure Container Registry
helm push my-chart-0.1.0.tgz oci://myregistry.azurecr.io/helm

# Install from OCI
helm install my-app oci://myregistry.azurecr.io/helm/my-chart --version 0.1.0
```

For regulated environments, OCI registries provide a single artifact store for both
container images and Helm charts, simplifying access control and audit logging.

### Release Namespaces

Helm stores release metadata (as Kubernetes Secrets) in the same namespace as the
release. This means RBAC on the namespace controls who can view or modify releases:

```bash
# Always specify --namespace explicitly
helm install my-app ./chart --namespace production
```

### Atomic Installs and Upgrades

The `--atomic` flag automatically rolls back a release if any resource fails to become
ready. Combined with `--timeout`, this prevents half-deployed releases:

```bash
helm upgrade my-app ./chart \
  --namespace production \
  --atomic \
  --timeout 5m
```

### Wait Flags

`--wait` blocks until all Pods, Services, and minimum Deployments are ready. Use this
in CI/CD pipelines to ensure deployments are healthy before proceeding:

```bash
helm install my-app ./chart --wait --timeout 3m
```

### Values Precedence

Helm merges values from multiple sources. Later sources override earlier ones:

1. Chart's `values.yaml` (lowest priority)
2. Parent chart's `values.yaml` (for subcharts)
3. `-f` / `--values` files (in order specified)
4. `--set` and `--set-string` flags (highest priority)

```bash
# File-based values override chart defaults; --set overrides everything
helm install my-app ./chart \
  -f values-production.yaml \
  --set image.tag=v2.0.1
```

## Example Chart

This directory includes an example Helm chart at [`example-chart/`](./example-chart/)
demonstrating a compliant web application deployment. The chart includes:

- **Security context** -- `runAsNonRoot`, `readOnlyRootFilesystem`, dropped capabilities
- **Resource limits** -- CPU and memory requests/limits to prevent resource exhaustion
- **Health probes** -- Liveness and readiness probes for reliable rolling updates
- **Templated labels** -- Standard Kubernetes labels for consistent resource identification

Install the example chart:

```bash
helm install hello-regulated ./example-chart \
  --namespace demo \
  --create-namespace \
  --wait
```

## EKS / GKE Notes

Helm works identically on AKS, EKS, GKE, and any conformant Kubernetes distribution.
It is a client-side tool that communicates with the standard Kubernetes API. No
cloud-specific configuration, plugins, or modifications are required. Charts, values
files, and release management behave the same across all providers.

## Certification Relevance

| Certification | Relevance |
|--------------|-----------|
| **CKAD** (Certified Kubernetes Application Developer) | Application deployment and management -- Helm is explicitly covered for chart usage, templating, and release lifecycle |
| **KCNA** (Kubernetes and Cloud Native Associate) | Kubernetes fundamentals -- understanding package management, application delivery, and the CNCF ecosystem |

## Learn More

- [Helm Documentation](https://helm.sh/docs/)
- [Artifact Hub](https://artifacthub.io/) -- discover and publish Kubernetes packages
- [CNCF Project Page](https://www.cncf.io/projects/helm/)
- [GitHub Repository](https://github.com/helm/helm)
- [Chart Template Guide](https://helm.sh/docs/chart_template_guide/) -- deep dive into Go templates
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
