<!-- ABOUTME: Complete matrix of all tools in the AKS regulated enterprise reference architecture. -->
<!-- ABOUTME: Lists tier, namespace, install method, ports, CNCF status, and cluster requirements. -->

# Tool Matrix

This reference lists every tool in the architecture with deployment details.

## Deployment Matrix

| Tier | Tool | Install Method | Namespace | Key Ports | CNCF Status | Cluster Required |
|------|------|----------------|-----------|-----------|-------------|------------------|
| Tier 1 | Falco | Helm (falcosecurity/falco) | falco | 8765 (gRPC) | Graduated | Yes |
| Tier 1 | Falcosidekick | Helm (falcosecurity/falcosidekick) | falco | 2801 (HTTP) | Sandbox | Yes |
| Tier 1 | Falco Talon | Helm (falcosecurity/falco-talon) | falco | 2803 (HTTP) | Community | Yes |
| Tier 1 | Kyverno | Helm (kyverno/kyverno) | kyverno | 9443 (webhook), 8000 (metrics) | Incubating | Yes |
| Tier 1 | Trivy Operator | Helm (aquasecurity/trivy-operator) | trivy-system | 8080 (metrics) | Community | Yes |
| Tier 1 | Kubescape | Helm (kubescape/kubescape-operator) | kubescape | 8080 (metrics) | Incubating | Yes |
| Tier 2 | Prometheus (kube-prometheus-stack) | Helm (prometheus-community/kube-prometheus-stack) | monitoring | 9090 (Prometheus), 3000 (Grafana), 9093 (Alertmanager) | Graduated | Yes |
| Tier 2 | ArgoCD | Helm (argo/argo-cd) | argocd | 443 (UI/API), 8080 (server) | Graduated | Yes |
| Tier 2 | External Secrets Operator | Helm (external-secrets/external-secrets) | external-secrets | 8080 (metrics) | Community | Yes |
| Tier 3 | Istio | Helm (istio/base + istio/istiod) | istio-system | 15010 (gRPC-XDS), 15012 (HTTPS-XDS), 15014 (control-plane metrics) | Graduated | Yes |
| Tier 3 | Crossplane | Helm (crossplane-stable/crossplane) | crossplane-system | 8080 (metrics) | Incubating | Yes |
| Tier 3 | Harbor | Helm (harbor/harbor) | harbor | 443 (portal), 4443 (notary) | Graduated | Yes |
| Tier 4 | Karpenter (AKS NAP) | Azure CLI + CRDs | kube-system | N/A (AKS-managed) | Incubating | Yes |
| Local | KubeHound | docker-compose | N/A (local) | 8182 (JanusGraph), 8183 (GraphExp) | Community | No |
| Local | Helm | CLI binary | N/A (client) | N/A | Graduated | No |
| Local | Kustomize | Built into kubectl | N/A (client) | N/A | Built-in | No |
| Docs | OPA Gatekeeper | Not auto-installed (Azure Policy) | gatekeeper-system | 8443 (webhook) | Graduated | Managed by Azure |
| Docs | Longhorn | Not auto-installed (EKS/GKE use) | longhorn-system | 9500 (UI) | Incubating | N/A |

## Tier Descriptions

- **Tier 1 -- Security Core**: Runtime detection, admission control, vulnerability scanning, compliance checking. Deployed first as the foundation.
- **Tier 2 -- Observability & Delivery**: Metrics collection, dashboards, GitOps pipelines, secret management. Depends on Tier 1 for ServiceMonitor targets.
- **Tier 3 -- Platform Services**: Service mesh, infrastructure-as-code, container registry. Depends on Tier 2 for monitoring.
- **Tier 4 -- AKS-Managed**: Features enabled at the Azure control plane level. Requires Terraform or Azure CLI.
- **Local**: Tools that run outside the cluster on the operator's workstation.
- **Docs Only**: Reference documentation provided but not auto-deployed. Azure Policy manages Gatekeeper; Longhorn is for non-AKS clusters.

## Install Commands

```bash
# Full install (all tiers)
./scripts/install-tools.sh

# Install specific tiers
./scripts/install-tools.sh --tier=1    # Security
./scripts/install-tools.sh --tier=2    # Observability
./scripts/install-tools.sh --tier=3    # Platform
./scripts/install-tools.sh --tier=4    # AKS-managed

# Or use make
make install           # All tiers
make install-tier1     # Security only
```
