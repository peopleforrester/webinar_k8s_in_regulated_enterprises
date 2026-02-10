# Kyverno

> **CNCF Status:** Incubating
> **Category:** Policy Engine
> **Difficulty:** Intermediate
> **AKS Compatibility:** Supported

## What It Does

Kyverno is a Kubernetes-native policy engine that validates, mutates, and generates
resources at admission time using standard YAML policies. Unlike OPA/Gatekeeper which
requires Rego, Kyverno policies are written in the same YAML syntax that Kubernetes
users already know, making policy authoring accessible to platform engineers and
auditors alike.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Least privilege enforcement, cybersecurity controls, change management, supply chain risk |
| SOC 2 | CC6.1 Logical access controls — policies enforce who/what can run in the cluster |
| DORA | ICT risk management Articles 5-7, Article 9 (access control), Article 11 (capacity) |
| PCI-DSS | Requirement 2.2 system hardening standards, configuration management |

## Architecture

Kyverno deploys as a set of controllers in the `kyverno` namespace:

```
+------------------+     +------------------+     +------------------+
| Admission        |     | Background       |     | Reports          |
| Controller       |     | Controller       |     | Controller       |
| (3 replicas)     |     | (2 replicas)     |     | (1 replica)      |
+--------+---------+     +--------+---------+     +--------+---------+
         |                        |                        |
         v                        v                        v
   Validates/mutates        Scans existing           Aggregates results
   resources at             resources for            into PolicyReport
   admission time           compliance               CRDs
```

- **Admission Controller** -- Intercepts API server requests via a validating/mutating
  webhook. Every `kubectl apply` passes through Kyverno before the resource is persisted.
- **Background Controller** -- Periodically scans existing resources against policies,
  catching resources created before policies were deployed.
- **Reports Controller** -- Produces `PolicyReport` and `ClusterPolicyReport` CRDs
  (Kubernetes Policy WG standard) that serve as machine-readable compliance evidence.

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured

### Install

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  -f values.yaml
```

### Apply Policies

```bash
kubectl apply -k policies/
```

### Verify

```bash
# Confirm Kyverno pods are running
kubectl get pods -n kyverno

# List deployed policies and their enforcement mode
kubectl get clusterpolicies -o wide

# Check policy reports for violations
kubectl get policyreport -A
kubectl get clusterpolicyreport
```

## Policies in This Repo

This repository includes 6 Kyverno `ClusterPolicy` resources, each annotated with
regulatory compliance mappings (`compliance.regulated/ncua`, `compliance.regulated/dora`,
etc.). They are deployed together via Kustomize (`kubectl apply -k policies/`).

### Enforce Mode (4 policies -- block non-compliant resources)

| Policy | What It Prevents | Regulatory Mapping |
|--------|-----------------|-------------------|
| `disallow-privileged-containers` | Containers running with `privileged: true`, which grants full host access | NCUA Cybersecurity, DORA Art.9 |
| `require-run-as-nonroot` | Containers running as UID 0 (root), reducing exploit severity | NCUA Least Privilege, DORA Art.9(4)(c) |
| `disallow-latest-tag` | Use of `:latest` image tag, ensuring deployment reproducibility | NCUA Change Mgmt, DORA Art.9(4)(e) |
| `require-resource-limits` | Pods without CPU/memory limits, preventing resource exhaustion | NCUA Resilience, DORA Art.11 |

### Audit Mode (2 policies -- report violations without blocking)

| Policy | What It Reports | Why Audit Mode |
|--------|----------------|---------------|
| `require-image-digest` | Images referenced by tag instead of SHA256 digest | Requires CI/CD tooling to produce digest-pinned manifests |
| `require-readonly-rootfs` | Containers without `readOnlyRootFilesystem: true` | Requires application changes to write to mounted volumes instead |

Audit-mode policies are stretch goals. Switch to `Enforce` once your tooling and
applications support the requirement.

## Key Configuration Decisions

Configuration is in [`values.yaml`](./values.yaml). Key settings:

- **Admission controller replicas: 3** -- The webhook is in the critical path for all
  cluster mutations. Three replicas with anti-affinity survive node failures without
  blocking deployments.
- **Background controller replicas: 2** -- Ensures continuous scanning of existing
  resources for compliance, even if one replica is unavailable.
- **PolicyReports enabled** -- Generates standard `PolicyReport` CRDs for compliance
  dashboards and audit evidence.
- **ValidatingAdmissionPolicy (VAP) generation: disabled** -- VAP auto-generation is
  Beta in Kyverno 1.17.0. When enabled, compatible policies execute at the API server
  level without webhook round-trips. Enable when your cluster runs Kubernetes 1.30+
  and you want reduced webhook latency.
- **Namespace exclusions** -- `kube-system` and `kyverno` are excluded from webhook
  enforcement to prevent bootstrap chicken-and-egg problems. Security tool namespaces
  (`falco`, `trivy-system`, `kubescape`) are excluded at the policy level because they
  may legitimately require elevated privileges.
- **Enforce vs Audit** -- Policies with clear, non-negotiable security requirements use
  `Enforce`. Policies that require tooling changes before adoption use `Audit`.
- **ServiceMonitor: disabled** -- Enable when prometheus-operator is installed.

## Testing Policies

```bash
# Dry-run with Kyverno CLI against local manifests
kyverno apply policies/ --resource ../../workloads/vulnerable-app/deployment.yaml

# View detailed policy violations in cluster
kubectl get policyreport -A -o json | \
    jq '.items[].results[] | select(.result == "fail")'
```

## EKS / GKE Notes

Kyverno works identically on EKS, GKE, and any conformant Kubernetes distribution.
No cloud-specific configuration is required. The Helm chart, policies, and Kustomize
overlay all apply without modification. The only consideration is ensuring the webhook
port (443) is reachable from the API server, which is the default on all managed
Kubernetes services.

## Certification Relevance

| Certification | Relevance |
|--------------|-----------|
| **CKS** (Certified Kubernetes Security Specialist) | Cluster setup and hardening -- admission controllers, Pod Security Standards, policy enforcement |
| **KCSA** (Kubernetes and Cloud Native Security Associate) | Understanding admission webhooks, policy-as-code, supply chain security concepts |

## Learn More

- [Kyverno Documentation](https://kyverno.io/docs/)
- [CNCF Project Page](https://www.cncf.io/projects/kyverno/)
- [GitHub Repository](https://github.com/kyverno/kyverno)
- [Kyverno Playground](https://playground.kyverno.io/) -- test policies in the browser
- [Policy Library](https://kyverno.io/policies/) -- community-maintained policy catalog
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
