# OPA Gatekeeper

> **CNCF Status:** Graduated (OPA is Graduated; Gatekeeper is a subproject)
> **Category:** Policy Engine
> **Difficulty:** Advanced
> **AKS Compatibility:** Native (Azure Policy for AKS uses Gatekeeper)

## What It Does

OPA Gatekeeper is a Kubernetes admission controller that enforces policies written
in Rego, the policy language of the Open Policy Agent (OPA) project. Policies are
defined in two layers: a `ConstraintTemplate` declares the policy logic in Rego,
and a `Constraint` instantiates that template with specific parameters and scope.
This architecture is more powerful and flexible than alternatives like Kyverno, but
carries a steeper learning curve due to the Rego language.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Access controls and least privilege enforcement, system hardening, configuration management |
| SOC 2 | CC6.1 Logical access controls -- policies enforce what workloads can run and how |
| DORA | Article 9 ICT risk management (access control, protection against misconfigurations) |
| PCI-DSS | Requirement 2.2 System hardening standards, secure configuration baselines |

## Architecture

Gatekeeper runs as a set of pods in the `gatekeeper-system` namespace:

```
                     +---------------------------+
                     |   Kubernetes API Server   |
                     +------------+--------------+
                                  |
                   AdmissionReview (webhook call)
                                  |
                                  v
                     +---------------------------+
                     |   Gatekeeper Webhook       |
                     |   (ValidatingWebhook)      |
                     |   (2+ replicas for HA)     |
                     +------------+--------------+
                                  |
              +-------------------+-------------------+
              |                                       |
              v                                       v
+---------------------------+           +---------------------------+
| ConstraintTemplate CRDs   |           | Audit Controller          |
| (define Rego policy logic) |           | (periodic background scan)|
+---------------------------+           +---------------------------+
              |                                       |
              v                                       v
+---------------------------+           +---------------------------+
| Constraint CRDs            |           | Audit results stored as   |
| (instantiate templates     |           | status.violations on      |
| with params + scope)       |           | each Constraint CR        |
+---------------------------+           +---------------------------+
```

**How enforcement works:**

1. A cluster admin creates a `ConstraintTemplate` containing Rego policy logic.
   Gatekeeper compiles the Rego and generates a new CRD kind (e.g., `K8sDisallowPrivileged`).
2. The admin creates a `Constraint` of that kind, specifying which resources to
   match and any parameters the Rego expects.
3. When a user submits a resource to the API server, the validating webhook
   evaluates the resource against all matching Constraints.
4. If any Constraint is violated, the request is denied (or flagged, in dry-run mode).
5. The audit controller periodically re-evaluates existing resources and records
   violations on the Constraint's `status.violations` field.

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured

### Install

```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  -f values.yaml
```

### Apply a ConstraintTemplate and Constraint

```bash
# Apply the ConstraintTemplate first (defines the Rego policy logic)
kubectl apply -f constraint-templates/disallow-privileged.yaml

# Wait for the CRD to be established
kubectl wait --for=condition=established \
  crd/k8sdisallowprivileged.constraints.gatekeeper.sh --timeout=60s

# Apply the Constraint (instantiates the template with scope and parameters)
kubectl apply -f constraints/disallow-privileged.yaml
```

### Verify

```bash
# Confirm Gatekeeper pods are running
kubectl get pods -n gatekeeper-system

# List ConstraintTemplates
kubectl get constrainttemplates

# List Constraints and their violation counts
kubectl get constraints

# Check audit violations on a specific constraint
kubectl describe k8sdisallowprivileged disallow-privileged-containers
```

## Gatekeeper vs Kyverno

| Aspect | OPA Gatekeeper | Kyverno |
|--------|---------------|---------|
| **Policy Language** | Rego (purpose-built policy language) | YAML (Kubernetes-native) |
| **Learning Curve** | Steep -- Rego requires dedicated learning | Low -- standard K8s YAML syntax |
| **Validation** | Full Rego expressiveness, cross-resource logic | JMESPath, CEL, pattern matching |
| **Mutation** | Beta (Gatekeeper 3.17+) | Stable and widely used |
| **Resource Generation** | Not supported | Supported (create related resources) |
| **Image Verification** | Not built-in (requires external tools) | Built-in (cosign, notation) |
| **Audit / Background Scan** | Built-in (violations on Constraint status) | Built-in (PolicyReport CRDs) |
| **Compliance Reporting** | Constraint status + audit logs | PolicyReport / ClusterPolicyReport CRDs |
| **AKS Integration** | Native -- Azure Policy for AKS is built on Gatekeeper | Supported via Helm (no native integration) |
| **GKE Integration** | Native -- GKE Policy Controller is Gatekeeper-based | Supported via Helm |
| **EKS Integration** | Supported via Helm (no native integration) | Supported via Helm (no native integration) |
| **CNCF Status** | Graduated (OPA) | Incubating |
| **Community Size** | Larger (OPA ecosystem spans beyond K8s) | Growing (K8s-focused) |
| **Policy Library** | [Gatekeeper Library](https://github.com/open-policy-agent/gatekeeper-library) | [Kyverno Policies](https://kyverno.io/policies/) |

**When to choose Gatekeeper:**
- Your organization already uses OPA for non-Kubernetes policy decisions
- You need Azure Policy for AKS (Gatekeeper is the underlying engine)
- You require complex cross-resource policy logic that Rego handles well
- You value the maturity and breadth of the OPA ecosystem

**When to choose Kyverno:**
- Your team does not know Rego and prefers YAML-based policies
- You need mutation and generation capabilities (stable in Kyverno)
- You want PolicyReport CRDs for standardized compliance reporting
- You value faster time-to-first-policy for platform engineering teams

## Key Configuration Decisions

Configuration is in [`values.yaml`](./values.yaml). Key settings:

- **Audit interval: 60 seconds** -- How often the audit controller re-evaluates existing
  resources. Lower values give faster detection but increase API server load. The default
  of 60s balances compliance visibility with cluster performance.

- **Exempt namespaces: kube-system, gatekeeper-system** -- System namespaces are excluded
  from policy enforcement to prevent bootstrap problems. Gatekeeper's own namespace must
  be excluded to prevent self-lockout.

- **Dry-run mode** -- Constraints support `enforcementAction: dryrun` to log violations
  without denying requests. Use this during rollout to assess policy impact before enforcing.

- **Referential data (Config resource)** -- Gatekeeper can sync cluster resources (Namespaces,
  Ingresses, etc.) into OPA's data store, enabling cross-resource policies (e.g., "no two
  Ingresses may share the same hostname"). Syncing too many resource types increases memory
  usage and audit latency.

- **Mutation support (beta)** -- Gatekeeper 3.17+ supports mutating admission via `Assign`
  and `AssignMetadata` CRDs. This is still beta and disabled by default in this configuration.
  For stable mutation, consider Kyverno instead.

- **Constraint violations limit: 20** -- Maximum violations stored per Constraint in the
  status field. Increase for large clusters with many existing violations, but be aware of
  etcd object size limits.

- **Disabled Rego builtins** -- For security, certain Rego builtins like `http.send` are
  disabled to prevent policies from making external network calls.

- **ServiceMonitor: disabled** -- Enable when prometheus-operator is installed.

## Policies in This Repo

This repository includes example ConstraintTemplates and Constraints for common
regulated-industry requirements:

| ConstraintTemplate | Constraint | What It Enforces | Regulatory Mapping |
|-------------------|-----------|-----------------|-------------------|
| `K8sDisallowPrivileged` | `disallow-privileged-containers` | Blocks containers with `privileged: true` | NCUA Cybersecurity, DORA Art.9, PCI-DSS 2.2 |
| `K8sRequireResourceLimits` | `require-resource-limits` | Requires CPU and memory limits on all containers | NCUA Resilience, DORA Art.11, SOC 2 CC7.1 |

## EKS / GKE Notes

OPA Gatekeeper works on any conformant Kubernetes distribution. Cloud-specific considerations:

- **AKS** -- Azure Policy for AKS is built on Gatekeeper. When you enable Azure Policy on an
  AKS cluster, Microsoft deploys Gatekeeper with pre-built Azure policy definitions. You can
  use Azure Policy alongside custom ConstraintTemplates, but be aware of potential conflicts
  with Azure-managed Constraints.

- **GKE** -- Google provides Policy Controller, a managed Gatekeeper distribution with
  additional features (policy bundles, dashboard integration). It can be enabled via GKE
  Fleet management or as a standalone add-on.

- **EKS** -- No native Gatekeeper integration. Install via Helm as shown in the Quick Start
  section. The Helm chart and all ConstraintTemplates/Constraints apply without modification.

## Certification Relevance

| Certification | Relevance |
|--------------|-----------|
| **CKS** (Certified Kubernetes Security Specialist) | Admission control, OPA Gatekeeper, Pod Security Standards, validating webhooks |
| **KCSA** (Kubernetes and Cloud Native Security Associate) | Policy-as-code concepts, admission controllers, understanding OPA and Rego basics |

## Learn More

- [Open Policy Agent Documentation](https://www.openpolicyagent.org/docs/latest/)
- [Gatekeeper Documentation](https://open-policy-agent.github.io/gatekeeper/website/docs/)
- [CNCF OPA Project Page](https://www.cncf.io/projects/open-policy-agent/)
- [Gatekeeper Policy Library](https://github.com/open-policy-agent/gatekeeper-library)
- [Rego Playground](https://play.openpolicyagent.org/) -- test Rego policies in the browser
- [Azure Policy for AKS](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/policy-for-kubernetes)
- [GKE Policy Controller](https://cloud.google.com/kubernetes-engine/docs/concepts/policy-controller)
