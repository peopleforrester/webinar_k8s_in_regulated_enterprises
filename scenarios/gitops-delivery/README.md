# GitOps Delivery Pipeline

> **Tools:** ArgoCD + Kustomize + Trivy
> **Category:** Cross-Tool Scenario
> **Difficulty:** Intermediate
> **Goal:** Wire together a regulated continuous delivery pipeline where Git is the single source of truth, environment configs are declarative overlays, and vulnerable images are blocked before reaching the cluster.

## Overview

A regulated GitOps delivery pipeline enforces one principle: **nothing reaches the cluster
unless it is declared in Git, built from reviewed overlays, and scanned for vulnerabilities.**

Three tools divide the work:

- **ArgoCD** continuously reconciles the cluster state with a Git repository. It detects
  drift, provides an audit trail of every sync, and ensures that manual `kubectl apply`
  changes are reverted to the declared state.
- **Kustomize** provides environment-specific overlays (development, staging, production)
  on top of a shared base manifest. Each environment gets its own resource limits, replica
  counts, and security context without duplicating YAML.
- **Trivy Operator** scans every container image running in the cluster for CVEs and
  generates VulnerabilityReports as Kubernetes custom resources. Combined with a Kyverno
  policy (or a pre-sync webhook), Trivy gates deployments that contain critical
  vulnerabilities.

Together they satisfy the regulatory requirement that all production changes are versioned,
reviewed, environment-separated, and vulnerability-assessed before deployment.

## Architecture

```
Developer pushes code
        |
        v
+-------------------+
|  Git Repository   |   (Kustomize base + overlays committed here)
|  - base/          |
|  - overlays/prod/ |
+--------+----------+
         |
         | ArgoCD watches for changes (polling or webhook)
         v
+-------------------+       +---------------------+
|  ArgoCD Server    | ----> | Kustomize Build     |
|  (detects diff)   |       | (renders overlays   |
|                   |       |  into final YAML)   |
+--------+----------+       +----------+----------+
         |                              |
         |   ArgoCD syncs manifests     |
         v                              v
+-------------------------------------------+
|  AKS Cluster                              |
|                                           |
|  +------------------+  +--------------+   |
|  | Trivy Operator   |  | Deployed     |   |
|  | scans new images |  | Workloads    |   |
|  +--------+---------+  +--------------+   |
|           |                               |
|           v                               |
|  +------------------+                     |
|  | VulnerabilityReport (CR)               |
|  | - blocks promotion if CRITICAL CVEs    |
|  +------------------+                     |
+-------------------------------------------+
```

**Flow summary:**

1. Developer opens a PR that modifies manifests or image tags under `overlays/production/`.
2. PR is reviewed and merged (satisfying change management controls).
3. ArgoCD detects the new commit and runs `kustomize build` against the target overlay.
4. ArgoCD syncs the rendered manifests to the cluster.
5. Trivy Operator detects the new pod, scans its image, and creates a VulnerabilityReport.
6. If critical CVEs are found, a Kyverno policy can block the deployment or flag it for review.

## Prerequisites

Complete the individual tool setup before running this scenario:

| Tool | Setup Guide |
|------|-------------|
| ArgoCD | [tools/argocd/](../../tools/argocd/) |
| Kustomize | [tools/kustomize/](../../tools/kustomize/) |
| Trivy Operator | [tools/trivy/](../../tools/trivy/) |

You will also need:
- An AKS cluster running (see [infrastructure/terraform/](../../infrastructure/terraform/))
- `kubectl`, `helm`, and `argocd` CLI tools installed
- A Git repository accessible from the cluster (this repo or a fork)

## Walkthrough

### Step 1: Deploy ArgoCD

Install ArgoCD into the cluster. See [tools/argocd/](../../tools/argocd/) for full
instructions. The minimal path:

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=120s

# Retrieve the initial admin password
argocd admin initial-password -n argocd
```

### Step 2: Create Kustomize Overlays

This repository already includes Kustomize base and overlays under
[tools/kustomize/](../../tools/kustomize/). The structure:

```
tools/kustomize/
  base/                     # Shared resource definitions
    kustomization.yaml
    namespace.yaml
    deployment.yaml
    service.yaml
  overlays/
    development/            # Low resource limits, 1 replica
      kustomization.yaml
    production/             # High limits, 3 replicas, security context
      kustomization.yaml
      security-patch.yaml
```

Preview what the production overlay produces:

```bash
kubectl kustomize tools/kustomize/overlays/production/
```

### Step 3: Install Trivy Operator

Deploy Trivy Operator so that every new pod is automatically scanned. See
[tools/trivy/](../../tools/trivy/) for the full values file.

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update

helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  -f tools/trivy/values.yaml
```

Verify it is scanning:

```bash
kubectl get vulnerabilityreports -A
```

### Step 4: Create an ArgoCD Application Pointing to the Kustomize Overlay

This is the step that connects ArgoCD to your Kustomize overlays. Create an ArgoCD
Application resource that points to the production overlay:

```bash
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-app-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/peopleforrester/aks-for-regulated-enterprises.git
    targetRevision: main
    path: tools/kustomize/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: demo-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

Key fields: `source.path` points to the Kustomize overlay directory. `syncPolicy.automated`
enables auto-sync with self-heal (reverts manual drift). ArgoCD runs `kustomize build`
on the overlay path and syncs the resulting manifests to the `demo-app` namespace.

### Step 5: Make a Change, Watch ArgoCD Sync

Push a change to the overlay (e.g., bump the replica count) and observe ArgoCD detect
and apply it:

```bash
# Check current sync status
argocd app get demo-app-production

# After pushing a change to Git, ArgoCD detects it within ~3 minutes (default poll)
# or immediately if a webhook is configured.

# Watch the sync happen
argocd app get demo-app-production --refresh
kubectl get pods -n demo-app -w
```

### Step 6: Push a Vulnerable Image, See Trivy Flag It

Update the image tag in the Kustomize overlay to reference an image with known
vulnerabilities:

```bash
# In overlays/production/kustomization.yaml, change the image to:
#   images:
#     - name: nginx
#       newTag: "1.14.0"    # Known vulnerable version

# After ArgoCD syncs the change, Trivy Operator scans the new image:
kubectl get vulnerabilityreports -n demo-app

# View the CVE details:
kubectl get vulnerabilityreport -n demo-app -o wide
```

To block vulnerable images at admission time, pair Trivy with a Kyverno policy that
checks VulnerabilityReports before allowing pod creation. See
[tools/kyverno/](../../tools/kyverno/) for policy examples.

## Regulatory Value

This pipeline directly addresses change management and deployment integrity requirements
across multiple regulatory frameworks:

| Requirement | How This Pipeline Satisfies It |
|-------------|-------------------------------|
| **NCUA Supervisory Priorities** - Change management controls | Every change is a Git commit. PRs provide review trails. ArgoCD provides sync audit logs. No manual cluster changes persist. |
| **DORA Article 9** - ICT change management | Kustomize overlays enforce environment separation. ArgoCD automated sync ensures declared state matches live state. Trivy provides continuous vulnerability assessment. |
| **SOC 2 CC8.1** - Change management | Git history is the immutable change log. ArgoCD drift detection prevents unauthorized modifications. VulnerabilityReports provide evidence for auditors. |
| **FFIEC Cloud Guidance** - Configuration management | Declarative overlays eliminate configuration drift. ArgoCD self-heal reverts manual changes. |
| **PCI-DSS 6.4** - Separate environments | Kustomize base/overlay pattern enforces structural separation between development and production. |

The combination of Git-based change records (ArgoCD), declarative environment separation
(Kustomize), and continuous vulnerability evidence (Trivy) provides auditors with a
complete chain of custody from code commit to running workload.

## Learn More

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD + Kustomize Integration](https://argo-cd.readthedocs.io/en/stable/user-guide/kustomize/)
- [Kustomize Official Documentation](https://kubectl.docs.kubernetes.io/references/kustomize/)
- [Trivy Operator Documentation](https://aquasecurity.github.io/trivy-operator/)
- [CNCF GitOps Working Group](https://opengitops.dev/)
- [OpenGitOps Principles](https://github.com/open-gitops/documents/blob/main/PRINCIPLES.md)
