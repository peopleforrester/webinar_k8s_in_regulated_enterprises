<!-- ABOUTME: Contributor guide for adding tools and content to this repository. -->
<!-- ABOUTME: Covers directory layout, naming conventions, style rules, and testing. -->

# Contributing

This repository is a CNCF companion toolkit for the KodeKloud webinar
**"AKS for Regulated Enterprises in the Age of AI."** It provides Terraform
infrastructure, Helm values, example manifests, and demo scenarios for
security and compliance tools running on Azure Kubernetes Service.

## Adding a New Tool

### 1. Scaffold from the template

```bash
cp -r tools/_template tools/<tool-name>
```

Directory names **must** be lowercase and hyphenated (e.g., `opa-gatekeeper`,
`external-secrets`).

### 2. Fill in the README

Edit `tools/<tool-name>/README.md` following the structure in `tools/_template/README.md`.
At minimum, include:

- What the tool does and why it matters for regulated workloads.
- Installation command (Helm preferred).
- Key configuration decisions and their rationale.

### 3. Create `values.yaml`

Provide a Helm `values.yaml` that is ready for a production-like AKS cluster.

- **Target 300--500 lines** for production-grade tools; smaller utilities can be shorter.
- Every non-obvious setting gets a comment explaining **why** it is set that way,
  not just what it does.

```yaml
# Good
# Run as non-root to satisfy PodSecurity "restricted" profile
securityContext:
  runAsNonRoot: true

# Bad — restates the key without explaining the reason
# Set runAsNonRoot to true
securityContext:
  runAsNonRoot: true
```

### 4. Add example manifests (if applicable)

Place Kubernetes manifests in a `manifests/` subdirectory inside the tool
folder. These should be self-contained examples that demonstrate the tool in
action (e.g., a Kyverno `ClusterPolicy`, a Falco `FalcoRule`).

### 5. Update the root README

Add a row to the tool catalog table in `README.md` at the repository root.

### 6. Update docs/CERTIFICATIONS.md

If the tool maps to a CNCF certification or exam objective, add the mapping
to `docs/CERTIFICATIONS.md`.

## values.yaml Style Guide

| Rule | Example |
|------|---------|
| Comment explains **why**, not what | `# Disable service monitor — no prometheus-operator installed` |
| Group related settings under a heading comment | `# -- Networking --` |
| Pin image tags to a digest or semver, never `latest` | `image.tag: "0.43.1"` |
| Disable optional features explicitly | `serviceMonitor.enabled: false` |

## Testing

All contributions must pass the following checks locally before pushing:

```bash
# Lint every YAML file
yamllint -d relaxed tools/<tool-name>/**/*.yaml

# Syntax-check every shell script
bash -n scripts/*.sh
```

If the tool includes Terraform, also run:

```bash
terraform -chdir=infrastructure/terraform validate
```

## Commit Messages

- Write clear, imperative-mood messages describing the technical change.
- Do not include AI attribution or tool references in commit messages.
- Keep the subject line under 72 characters; use the body for detail.

```
Add trivy values with PodSecurity-restricted settings

Configure Trivy Helm chart for AKS with non-root security contexts,
resource limits sized for a 3-node regulated cluster, and SBOM
generation enabled for supply-chain compliance.
```

## Questions

Open an issue or reach out in the KodeKloud community if anything is unclear.
