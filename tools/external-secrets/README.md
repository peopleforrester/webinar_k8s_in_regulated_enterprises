# External Secrets Operator

> **CNCF Status:** Community
> **Category:** Secrets Management
> **Difficulty:** Intermediate
> **AKS Compatibility:** Supported

## What It Does

External Secrets Operator (ESO) synchronizes secrets from external secret management
systems into Kubernetes Secrets. It supports providers including Azure Key Vault,
AWS Secrets Manager, HashiCorp Vault, and GCP Secret Manager. By pulling secrets at
runtime from a trusted external store, ESO keeps sensitive material out of Git
repositories, Helm values files, and CI/CD pipelines entirely.

The operator watches `ExternalSecret` custom resources, fetches the referenced values
from the configured provider, and creates or updates native Kubernetes `Secret` objects.
When the external value changes (e.g., a rotated database password in Key Vault), ESO
detects the change on the next refresh interval and updates the Kubernetes Secret
automatically -- enabling zero-touch secret rotation.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|--------------------|
| NCUA/FFIEC | Credential management, secret rotation, separation of duties (secrets stored outside application code) |
| SOC 2 | CC6.1 Logical access controls -- secrets retrieved via identity-based auth, not embedded in manifests; CC6.7 Secrets management -- centralized lifecycle management |
| DORA | Article 9 Access control and data protection -- secrets governed by provider IAM, not cluster RBAC alone |
| PCI-DSS | Requirement 3.4 Protect stored credentials -- secrets encrypted at rest in provider vaults; Requirement 8 Access control -- workload identity scoped per-application |

## Architecture

```
                           +---------------------------+
                           |   Azure Key Vault         |
                           |   (or AWS SM / GCP SM /   |
                           |    HashiCorp Vault)       |
                           +------------+--------------+
                                        ^
                                        | HTTPS (TLS 1.2+)
                                        | Workload Identity
                                        | (Federated OIDC Token)
                                        |
+---------------------+     +-----------+-----------+
|  ExternalSecret     |---->|  External Secrets     |
|  (Custom Resource)  |     |  Operator Controller  |
|  - secretStoreRef   |     |  (Deployment)         |
|  - data[].remoteRef |     +-----------+-----------+
|  - refreshInterval  |                 |
+---------------------+                 | Creates / Updates
                                        v
+-----------------------+     +---------+-----------+
|  SecretStore /        |     |  Kubernetes Secret  |
|  ClusterSecretStore   |     |  (native Secret)    |
|  - provider: azurekv  |     |  - owned by ESO     |
|  - auth: workloadId   |     |  - auto-rotated     |
+-----------------------+     +---------------------+
```

- **SecretStore / ClusterSecretStore** -- Defines the connection to an external
  provider (vault URL, auth method, region). `ClusterSecretStore` is cluster-scoped
  and can be referenced from any namespace. `SecretStore` is namespace-scoped.
- **ExternalSecret** -- Declares which secrets to fetch, how often to refresh, and
  what Kubernetes Secret to write them into. Maps remote keys to local Secret keys.
- **Operator Controller** -- Reconciles ExternalSecret resources, authenticates to
  the provider, fetches values, and manages the target Kubernetes Secret lifecycle.

## Quick Start (AKS)

### Prerequisites

- AKS cluster with workload identity enabled (see [infrastructure/terraform](../../infrastructure/terraform/))
- Azure Key Vault with secrets populated
- Managed identity with `Key Vault Secrets User` role on the vault
- Federated identity credential linking the Kubernetes service account to the managed identity
- Helm 3.x installed
- kubectl configured

### Install

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  -f values.yaml
```

### Create a ClusterSecretStore

```bash
kubectl apply -f manifests/cluster-secret-store.yaml
```

### Create an ExternalSecret

```bash
kubectl apply -f manifests/external-secret.yaml
```

### Verify

```bash
# Confirm operator pods are running
kubectl get pods -n external-secrets

# Check SecretStore connectivity
kubectl get clustersecretstore -o wide

# Check ExternalSecret sync status
kubectl get externalsecret -A

# Verify the Kubernetes Secret was created with the expected keys
kubectl get secret database-credentials -n demo -o jsonpath='{.data}' | jq .
```

## Key Configuration Decisions

- **ClusterSecretStore vs SecretStore** -- `ClusterSecretStore` is cluster-scoped: one
  store serves all namespaces. `SecretStore` is namespace-scoped and limits blast radius.
  For regulated environments, prefer namespace-scoped `SecretStore` resources so each
  team's workload identity can only access its own vault scope. Use `ClusterSecretStore`
  only for shared infrastructure secrets.
- **Refresh interval** -- Controls how often ESO polls the provider for changes.
  `1h` is a reasonable default. For secrets that rotate frequently (e.g., short-lived
  database tokens), use `5m` or less. For static secrets, `24h` reduces API calls.
  Provider API rate limits apply.
- **Secret rotation** -- ESO detects changes on the next refresh interval and updates
  the Kubernetes Secret automatically. Applications must reload secrets (via volume
  mount inotify, sidecar reloader, or pod restart) to pick up new values.
- **Workload identity vs service principal** -- On AKS, workload identity (federated
  OIDC) is the recommended auth method. It eliminates long-lived client secrets
  entirely. Service principal auth requires a client secret stored as a Kubernetes
  Secret, creating a bootstrap chicken-and-egg problem for the first secret.
- **Secret ownership** -- ESO sets `ownerReference` on created Secrets. Deleting the
  ExternalSecret deletes the Secret. Set `deletionPolicy: Retain` if Secrets must
  survive ExternalSecret deletion.
- **ServiceMonitor: disabled** -- Enable when prometheus-operator is installed.

## EKS / GKE Notes

External Secrets Operator works identically across all conformant Kubernetes
distributions. The only difference is the provider configuration:

| Cloud | Provider | Auth Method |
|-------|----------|-------------|
| AKS | `azurekv` | Workload Identity (federated OIDC) |
| EKS | `aws` (Secrets Manager or Parameter Store) | IRSA (IAM Roles for Service Accounts) |
| GKE | `gcpsm` (GCP Secret Manager) | Workload Identity Federation |

The Helm chart, CRDs, and operator deployment are identical. Only the
`SecretStore.spec.provider` block changes per cloud.

## Certification Relevance

| Certification | Relevance |
|---------------|-----------|
| **CKS** (Certified Kubernetes Security Specialist) | Secrets management, encryption at rest, minimizing secret exposure in manifests and etcd |
| **KCSA** (Kubernetes and Cloud Native Security Associate) | Understanding Kubernetes Secrets lifecycle, external secret stores, workload identity concepts |

## Learn More

- [External Secrets Operator Documentation](https://external-secrets.io/latest/)
- [GitHub Repository](https://github.com/external-secrets/external-secrets)
- [Azure Key Vault Provider Guide](https://external-secrets.io/latest/provider/azure-key-vault/)
- [AWS Secrets Manager Provider Guide](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- [GCP Secret Manager Provider Guide](https://external-secrets.io/latest/provider/google-secrets-manager/)
- [HashiCorp Vault Provider Guide](https://external-secrets.io/latest/provider/hashicorp-vault/)
- [AKS Workload Identity Documentation](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
