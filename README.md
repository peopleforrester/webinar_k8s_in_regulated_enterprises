# AKS for Regulated Enterprises — CNCF Companion Toolkit

> Companion repository for the KodeKloud webinar **"AKS for Regulated Enterprise in the Age of AI"**

A take-home reference with runnable Helm values, Kubernetes manifests, and educational documentation for **15+ CNCF and cloud-native tools** deployed on Azure Kubernetes Service. Every tool directory includes a README explaining what it does, why it matters for regulated industries, and how to install it on an AKS cluster.

## Quick Start

```bash
# 1. Clone
git clone https://github.com/peopleforrester/webinar_k8s_in_regulated_enterprises.git
cd webinar_k8s_in_regulated_enterprises

# 2. Deploy an AKS cluster (~10 min)
./scripts/setup-cluster.sh

# 3. Pick a tool and follow its README
ls tools/
```

See [QUICKSTART.md](QUICKSTART.md) for detailed step-by-step instructions including prerequisites.

---

## Tool Catalog

### Security & Compliance

| Tool | CNCF Status | Difficulty | Directory | Description |
|------|-------------|------------|-----------|-------------|
| **Kyverno** | Incubating | Intermediate | [tools/kyverno/](tools/kyverno/) | Policy engine — validate, mutate, generate K8s resources at admission |
| **OPA Gatekeeper** | Graduated | Advanced | [tools/opa-gatekeeper/](tools/opa-gatekeeper/) | Policy engine using Rego — ConstraintTemplates and Constraints |
| **Falco** | Graduated | Intermediate | [tools/falco/](tools/falco/) | Runtime threat detection via eBPF syscall monitoring |
| **Falcosidekick** | Sandbox | Beginner | [tools/falcosidekick/](tools/falcosidekick/) | Alert router — forwards Falco events to 50+ destinations |
| **Falco Talon** | Community | Intermediate | [tools/falco-talon/](tools/falco-talon/) | Automated threat response — isolate pods, label for forensics |
| **Trivy** | Community | Beginner | [tools/trivy/](tools/trivy/) | Vulnerability scanner and SBOM generator (operator mode) |
| **Kubescape** | Incubating | Beginner | [tools/kubescape/](tools/kubescape/) | Compliance scanning against NSA, CIS, SOC2, MITRE frameworks |
| **KubeHound** | Community | Advanced | [tools/kubehound/](tools/kubehound/) | Attack path analysis — graph-based MITRE ATT&CK mapping |
| **Harbor** | Graduated | Advanced | [tools/harbor/](tools/harbor/) | Container registry with vulnerability scanning and RBAC |
| **External Secrets** | Community | Intermediate | [tools/external-secrets/](tools/external-secrets/) | Sync secrets from Azure Key Vault, AWS SM, GCP SM into K8s |

### Packaging & Delivery

| Tool | CNCF Status | Difficulty | Directory | Description |
|------|-------------|------------|-----------|-------------|
| **Helm** | Graduated | Beginner | [tools/helm/](tools/helm/) | Package manager — charts, values, release management |
| **Kustomize** | Built-in | Beginner | [tools/kustomize/](tools/kustomize/) | Template-free customization — base/overlay pattern |
| **ArgoCD** | Graduated | Intermediate | [tools/argocd/](tools/argocd/) | GitOps continuous delivery — declarative app management |

### Observability

| Tool | CNCF Status | Difficulty | Directory | Description |
|------|-------------|------------|-----------|-------------|
| **Prometheus** | Graduated | Intermediate | [tools/prometheus/](tools/prometheus/) | Metrics collection — kube-prometheus-stack with alerting |
| **Grafana** | Community | Beginner | [tools/grafana/](tools/grafana/) | Dashboards and visualization — cluster and security views |

### Infrastructure & Platform

| Tool | CNCF Status | Difficulty | Directory | Description |
|------|-------------|------------|-----------|-------------|
| **Istio** | Graduated | Advanced | [tools/istio/](tools/istio/) | Service mesh — mTLS, traffic management, authorization |
| **Karpenter** | Incubating | Intermediate | [tools/karpenter/](tools/karpenter/) | Node autoscaling — right-size nodes on demand |
| **Longhorn** | Incubating | Intermediate | [tools/longhorn/](tools/longhorn/) | Distributed block storage — replicated persistent volumes |
| **Crossplane** | Incubating | Advanced | [tools/crossplane/](tools/crossplane/) | Infrastructure as code — provision cloud resources from K8s |

---

## Cross-Tool Scenarios

These scenarios wire multiple tools together to solve real-world problems.

| Scenario | Tools Used | Directory |
|----------|-----------|-----------|
| **Attack, Detect, Prevent, Prove** | KubeHound + Falco + Kyverno + Kubescape | [scenarios/attack-detect-prevent/](scenarios/attack-detect-prevent/) |
| **GitOps Delivery Pipeline** | ArgoCD + Kustomize + Trivy | [scenarios/gitops-delivery/](scenarios/gitops-delivery/) |
| **Zero Trust Networking** | Istio + Kyverno + Falco | [scenarios/zero-trust/](scenarios/zero-trust/) |
| **FinOps Cost Optimization** | Karpenter + Prometheus + Grafana | [scenarios/finops/](scenarios/finops/) |

---

## Infrastructure

The `infrastructure/terraform/` directory deploys an AKS cluster with production-grade defaults:

| Setting | Configuration | Rationale |
|---------|--------------|-----------|
| Kubernetes | 1.34 | Latest GA, LTS-eligible |
| Network Policy | Cilium | eBPF-based L7 policies, replaces retiring Azure NPM |
| Node OS | AzureLinux | Azure Linux 2.0 retired Nov 2025 |
| Identity | Workload Identity | Pod-Managed Identity deprecated Sep 2025 |
| Image Cleaner | Enabled (7-day) | GA feature for vulnerability cleanup |

## Regulatory Compliance

This toolkit addresses requirements across multiple regulatory frameworks:

| Region | Regulation | Key Requirements |
|--------|------------|------------------|
| US | NCUA Supervisory Priorities | Cybersecurity controls, least privilege |
| US | FFIEC Cloud Guidance | Third-party risk, access controls |
| Canada | OSFI B-10, B-13, E-21 | Third-party risk, cyber risk, operational risk |
| EU | DORA (effective Jan 2025) | 4-hour incident reporting, ICT risk management |

See [docs/COMPLIANCE-MAPPING.md](docs/COMPLIANCE-MAPPING.md) for detailed control-to-tool mappings.

## CNCF Certifications

Every tool in this repo maps to one or more CNCF certification exam domains (CKA, CKAD, CKS, KCNA, KCSA). See [docs/CERTIFICATIONS.md](docs/CERTIFICATIONS.md).

## Repository Structure

```
├── infrastructure/terraform/     # AKS cluster (K8s 1.34, Cilium, AzureLinux)
├── tools/                        # One directory per tool (README + values + manifests)
│   ├── _template/                # Template for adding new tools
│   ├── kyverno/                  ├── argocd/
│   ├── falco/                    ├── prometheus/
│   ├── falcosidekick/            ├── grafana/
│   ├── falco-talon/              ├── istio/
│   ├── trivy/                    ├── karpenter/
│   ├── kubescape/                ├── longhorn/
│   ├── kubehound/                ├── harbor/
│   ├── helm/                     ├── crossplane/
│   ├── kustomize/                └── external-secrets/
│   └── opa-gatekeeper/
├── workloads/                    # Example applications
│   ├── vulnerable-app/           # Intentionally insecure (for policy demos)
│   └── compliant-app/            # Passes all security policies
├── scenarios/                    # Multi-tool walkthroughs
├── ci-cd/                        # Pipeline templates (Azure DevOps + GitHub Actions)
├── scripts/                      # Setup, install, cleanup automation
└── docs/                         # Compliance mappings, architecture, troubleshooting
```

## Prerequisites

```bash
az --version       # Azure CLI (authenticated)
terraform -v       # Terraform 1.5+
kubectl version    # kubectl
helm version       # Helm 3.x
```

## Cleanup

```bash
./scripts/cleanup.sh                  # Remove workloads and policies only
./scripts/cleanup.sh --reset-demo     # Reset for fresh demo run
./scripts/cleanup.sh --full --destroy # Full teardown including Azure infra
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a tool to this repository.

## Webinar

Watch the full webinar: *Link coming soon*

## License

MIT License — See [LICENSE](LICENSE)

## Contact

Michael Forrester — Senior Principal Trainer & DevOps Advocate, KodeKloud
michael.forrester@kodekloud.com
