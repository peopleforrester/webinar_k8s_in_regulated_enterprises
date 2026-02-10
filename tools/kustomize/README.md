# Kustomize

> **CNCF Status:** Built-in (kubectl)
> **Category:** Configuration Management
> **Difficulty:** Beginner
> **AKS Compatibility:** Native

## What It Does

Kustomize provides template-free customization of Kubernetes manifests using overlays,
patches, and transformers. Instead of parameterizing YAML with template syntax, you
maintain a clean base configuration and layer environment-specific changes on top. It is
built directly into `kubectl` via the `-k` flag, requiring no additional tooling.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Environment separation (dev/staging/prod), change management through declarative overlays |
| SOC 2 | CC6.1 Logical environment controls — identical base with auditable per-environment overrides |
| DORA | Article 9 ICT configuration management — versioned, reviewable config changes |
| PCI-DSS | Requirement 6.4 Separate development/test/production environments |

## Architecture

Kustomize uses a base-plus-overlays pattern. A `base/` directory contains the canonical
resource definitions. Each environment gets an `overlays/` directory that references the
base and applies targeted modifications:

```
kustomize/
├── base/
│   ├── kustomization.yaml      ← lists resources + labels
│   ├── namespace.yaml
│   ├── deployment.yaml
│   └── service.yaml
│
└── overlays/
    ├── development/
    │   └── kustomization.yaml  ← namePrefix: dev-, small limits, 1 replica
    ├── staging/
    │   └── kustomization.yaml  ← namePrefix: stg-, medium limits, 2 replicas
    └── production/
        ├── kustomization.yaml  ← namePrefix: prod-, large limits, 3 replicas
        └── security-patch.yaml ← security context hardening

                      kustomize build
  base/  ──────────────────┐
                            ├──►  Final merged manifests
  overlays/production/  ───┘     (ready for kubectl apply)
```

When you run `kustomize build overlays/production/`, Kustomize reads the base resources,
applies the overlay's patches, name transformations, and label injections, then emits the
final merged YAML. No intermediate templates or variable substitution are involved — the
output is deterministic and diffable.

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- kubectl configured (`az aks get-credentials --admin`)

### Build and Preview

```bash
# Preview the production overlay without applying
kubectl kustomize overlays/production/

# Equivalent standalone command
kustomize build overlays/production/
```

### Apply to Cluster

```bash
# Apply the development overlay
kubectl apply -k overlays/development/

# Apply the production overlay
kubectl apply -k overlays/production/

# Dry-run to see what would change
kubectl apply -k overlays/production/ --dry-run=client -o yaml
```

### Verify

```bash
# Confirm resources were created with the correct name prefix
kubectl get all -n demo-app

# Check that production pods have security context applied
kubectl get deployment prod-demo-app -n demo-app -o jsonpath='{.spec.template.spec.securityContext}'
```

## Key Configuration Decisions

- **Base vs Overlay separation** — The base contains only the resource structure common
  to every environment. Never put environment-specific values (replica counts, resource
  limits, image tags) in the base.
- **Patches vs Replacements** — Use strategic merge patches for adding or modifying
  fields (like security context). Use JSON patches or replacements when you need to
  change a specific value at a known path.
- **namePrefix / nameSuffix** — Prefixing resource names per environment (`dev-`, `prod-`)
  prevents collisions when multiple overlays deploy to the same cluster or namespace.
- **labels** — Apply consistent labels at the base level for selection and filtering.
  Use `includeSelectors: true` to inject into selector fields. Overlays can add
  environment-specific labels on top.
- **configMapGenerator / secretGenerator** — Generate ConfigMaps and Secrets from files
  or literals with automatic hash suffixes, triggering rolling updates when content changes.

## Kustomize vs Helm

| Aspect | Kustomize | Helm |
|--------|-----------|------|
| **Approach** | Declarative overlays on plain YAML | Parameterized Go templates |
| **Learning curve** | Low — uses standard YAML | Medium — requires template syntax |
| **Packaging** | No packaging concept | Charts with versioning and distribution |
| **Use case** | Internal config customization per environment | Distributing reusable application packages |
| **Combination** | Can post-process Helm output (`helm template \| kubectl apply -k`) | Can include Kustomize bases |

They complement each other. Use Helm to install third-party applications (Falco, Kyverno,
Trivy). Use Kustomize to manage your own application configurations across environments.

## EKS / GKE Notes

Kustomize is built into `kubectl` and operates entirely client-side. It works identically
on AKS, EKS, GKE, and any conformant Kubernetes distribution. No cloud-specific
configuration is needed — `kubectl apply -k` behaves the same everywhere.

## Certification Relevance

| Certification | Relevance |
|--------------|-----------|
| **CKAD** (Certified Kubernetes Application Developer) | Kustomize is explicitly on the exam — candidates must use `kubectl apply -k` and `kustomize build` |
| **CKA** (Certified Kubernetes Administrator) | Application deployment and lifecycle management using Kustomize overlays |
| **KCNA** (Kubernetes and Cloud Native Associate) | Understanding Kubernetes fundamentals including configuration management |

## Learn More

- [Kustomize Official Documentation](https://kubectl.docs.kubernetes.io/references/kustomize/)
- [kubectl Kustomize Reference](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
- [GitHub Repository](https://github.com/kubernetes-sigs/kustomize)
- [Kustomize Examples](https://github.com/kubernetes-sigs/kustomize/tree/master/examples)
- [The Kustomization File](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/)
