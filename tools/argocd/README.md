# Argo CD

> **CNCF Status:** Graduated
> **Category:** GitOps / Continuous Delivery
> **Difficulty:** Intermediate
> **AKS Compatibility:** Supported

## What It Does

Argo CD is a declarative, GitOps continuous delivery tool for Kubernetes. It
continuously monitors Git repositories and automatically synchronizes the live
cluster state to match the desired state defined in Git. Argo CD supports Helm
charts, Kustomize overlays, plain YAML manifests, and Jsonnet as manifest
sources, making it adaptable to any Kubernetes deployment workflow.

The core principle: **Git is the single source of truth.** Every change to
cluster state flows through a Git commit, providing a complete audit trail of
who changed what, when, and why.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Change management procedures, complete audit trail of all deployments, separation of duties between commit and deploy |
| SOC 2 | CC8.1 Change management -- all changes tracked in Git with approval workflows before cluster deployment |
| DORA | Article 9 ICT change management -- documented, tested, and approved changes with rollback capability |
| PCI-DSS | Requirement 6.5 Change control procedures -- immutable deployment records, version tracking, rollback history |

## Architecture

Argo CD deploys as a set of controllers in the `argocd` namespace:

```
+-------------------+     +-------------------+     +-------------------+
| Application       |     | Repo Server       |     | Redis             |
| Controller        |     |                   |     |                   |
| (reconcile loop)  |     | (manifest gen)    |     | (caching layer)   |
+--------+----------+     +--------+----------+     +--------+----------+
         |                         |                         |
         v                         v                         v
  Watches Application       Clones Git repos,         Caches manifests,
  CRDs, compares live       renders Helm/Kustomize    repo state, and
  state to desired          into plain manifests      app status
  state in Git

+-------------------+     +-------------------+
| Server (UI/API)   |     | Dex / SSO         |
|                   |     | (optional)        |
| (web dashboard,   |     |                   |
|  gRPC/REST API)   |     | (OIDC provider)   |
+--------+----------+     +--------+----------+
         |                         |
         v                         v
  Exposes dashboard          Integrates with
  and API for sync           Azure AD, Okta,
  operations, RBAC           LDAP for SSO

+-------------------+
| ApplicationSet    |
| Controller        |
|                   |
+--------+----------+
         |
         v
  Generates Application
  CRDs from templates
  (Git generators, etc.)
```

- **Application Controller** -- The core reconciliation engine. Watches `Application` CRDs
  and continuously compares the live cluster state against the desired state in Git. Triggers
  sync operations when drift is detected.
- **Repo Server** -- Clones Git repositories and renders manifests from Helm charts, Kustomize
  overlays, or plain YAML. Caches results in Redis to reduce Git operations.
- **Redis** -- In-memory cache for manifest rendering results, repository state, and application
  status. Reduces load on the Repo Server and Git providers.
- **Server (UI/API)** -- Provides the web-based dashboard and gRPC/REST API. Handles
  authentication, RBAC enforcement, and user-initiated operations (sync, rollback).
- **Dex / SSO** -- Optional OIDC identity provider that integrates with Azure AD, Okta, LDAP,
  and other identity providers for single sign-on.
- **ApplicationSet Controller** -- Generates multiple `Application` CRDs from templates using
  generators (Git directory, Git file, cluster, list, matrix, merge). Enables multi-cluster
  and multi-environment patterns.

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured

### Install

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f values.yaml
```

### Access the UI

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward to the Argo CD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open https://localhost:8080 in your browser
# Login: admin / <password from above>
```

### Create Your First Application

```bash
# Apply the sample Application CRD
kubectl apply -f manifests/application.yaml

# Or create via CLI
argocd app create compliant-app \
  --repo https://github.com/peopleforrester/aks-for-regulated-enterprises.git \
  --path workloads/compliant-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace compliant-app
```

### Verify

```bash
# Confirm Argo CD pods are running
kubectl get pods -n argocd

# List applications and their sync status
kubectl get applications -n argocd

# Check application health
argocd app get compliant-app
```

## Key Configuration Decisions

Configuration is in [`values.yaml`](./values.yaml). Key settings:

- **HA mode: disabled** -- Single replicas for lab/demo environments. Production deployments
  should enable HA with multiple replicas for the application controller, repo server, and
  Redis (sentinel mode). See the HA values in `values.yaml` for guidance.
- **SSO integration** -- Argo CD supports Azure AD, Okta, and LDAP via Dex. For regulated
  environments, SSO provides centralized identity management and MFA enforcement. See the
  commented Dex configuration in `values.yaml`.
- **RBAC** -- Role-based access control maps SSO groups to Argo CD roles. Define `admin`,
  `readonly`, and project-scoped roles to enforce separation of duties between teams.
- **Repository credentials** -- Configure SSH keys or HTTPS tokens for private Git repos.
  Azure DevOps repos use PAT tokens or SSH deploy keys.
- **Sync policies (auto vs manual)** -- Auto-sync deploys changes immediately on Git push.
  Manual sync requires explicit approval. Regulated environments typically use manual sync
  with approval gates, or auto-sync with mandatory PR reviews.
- **Prune and self-heal** -- Prune removes resources deleted from Git. Self-heal reverts
  manual changes made directly to the cluster (kubectl edits). Both enforce Git as the
  single source of truth.
- **Resource exclusions** -- Exclude certain resources from tracking (e.g., Events,
  EndpointSlices) to reduce noise and improve performance.
- **Notifications controller** -- Sends alerts on sync success/failure to Slack, Teams,
  email, or webhooks. Critical for operational awareness.

## Sample Manifests

This directory includes sample Argo CD CRDs in [`manifests/`](./manifests/):

| Manifest | Purpose |
|----------|---------|
| [`application.yaml`](./manifests/application.yaml) | Sample Application pointing to the compliant-app workload |
| [`applicationset.yaml`](./manifests/applicationset.yaml) | ApplicationSet using a Git generator for multi-directory deployments |
| [`project.yaml`](./manifests/project.yaml) | AppProject defining source/destination restrictions and RBAC roles |

## EKS / GKE Notes

Argo CD works identically on EKS, GKE, and any conformant Kubernetes distribution. No
cloud-specific configuration is required. The Helm chart, Application CRDs, and RBAC
settings all apply without modification.

Cloud-native alternatives exist but solve the same problem differently:
- **AWS**: Flux (CNCF Graduated) is commonly paired with EKS. AWS also offers CodePipeline.
- **GCP**: Config Sync is Google's built-in GitOps solution for GKE.
- **Azure**: Azure DevOps Pipelines with Flux extension, or Argo CD with Azure DevOps
  repo credentials (PAT tokens or SSH keys).

For multi-cloud GitOps, Argo CD's cloud-agnostic design is an advantage -- the same
Application CRDs and project configurations work across all providers.

## Certification Relevance

| Certification | Relevance |
|--------------|-----------|
| **CKAD** (Certified Kubernetes Application Developer) | Application deployment strategies, Helm usage, understanding declarative configuration |
| **KCNA** (Kubernetes and Cloud Native Associate) | GitOps concepts, continuous delivery principles, CNCF project ecosystem |

## Learn More

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [CNCF Project Page](https://www.cncf.io/projects/argo/)
- [GitHub Repository](https://github.com/argoproj/argo-cd)
- [Argo Project](https://argoproj.github.io/) -- Argo Workflows, Events, and Rollouts
- [GitOps Principles](https://opengitops.dev/) -- OpenGitOps specification
- [Argo CD Autopilot](https://argocd-autopilot.readthedocs.io/) -- opinionated bootstrapping tool
