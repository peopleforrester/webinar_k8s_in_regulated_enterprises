# AKS Regulated Enterprise Demo

> Companion repository for the KodeKloud webinar "AKS for Regulated Enterprise in the Age of AI"

## What This Repository Demonstrates

This repository provides a complete, deployable example of securing Azure Kubernetes Service (AKS) for regulated financial services environments using CNCF open source tools.

**Demo Narrative: Attack → Detect → Prevent → Prove**

1. **SEE** - Visualize attack paths with KubeHound
2. **DETECT** - Runtime threat detection with Falco + automated response with Talon
3. **PREVENT** - Policy enforcement with Kyverno
4. **PROVE** - Compliance validation with Kubescape

## The Security Stack (February 2026)

| Tool | Version | Purpose | Status |
|------|---------|---------|--------|
| **KubeHound** | 1.6.7 | Attack path analysis with MITRE ATT&CK mapping | Datadog OSS |
| **Falco** | 0.43.0 | Runtime threat detection (modern_ebpf driver) | CNCF Graduated |
| **Falco Talon** | 0.3.0 | Automated threat response | Falcosecurity |
| **Kyverno** | 1.17.0 | Policy-as-code with ValidatingAdmissionPolicy | CNCF Incubating |
| **Trivy** | 0.29.0 | Vulnerability scanning and SBOM generation | Aqua Security |
| **Kubescape** | 4.0.0 | Compliance posture (NSA, SOC2, CIS-v1.12.0) | CNCF Incubating |

## Infrastructure Configuration

This demo deploys AKS with February 2026 best practices:

| Setting | Configuration | Why |
|---------|--------------|-----|
| **Kubernetes** | 1.34 | Latest GA, LTS-eligible |
| **Network Policy** | Cilium | Replaces retiring Azure NPM, eBPF-based L7 policies |
| **Node OS** | AzureLinux | Azure Linux 2.0 retired Nov 2025 |
| **Image Cleaner** | Enabled (7-day) | GA feature for vulnerability cleanup |
| **Upgrade Channel** | stable | Required for AKS Automatic compatibility |
| **Identity** | Workload Identity | Pod-Managed Identity deprecated Sep 2025 |

## Quick Start (15 minutes)

See [QUICKSTART.md](QUICKSTART.md) for detailed instructions.

```bash
# Clone the repository
git clone https://github.com/peopleforrester/aks-for-regulated-enterprises.git
cd aks-for-regulated-enterprises

# Deploy AKS cluster (~10 min)
./scripts/setup-cluster.sh

# Install security tools (~5 min)
./scripts/install-tools.sh

# Deploy demo workloads
kubectl apply -f workloads/vulnerable-app/
kubectl apply -f workloads/compliant-app/

# Run the demo
./scripts/run-demo.sh
```

## Regulatory Compliance Mapping

This demo addresses requirements from:

| Region | Regulation | Key Requirements |
|--------|------------|------------------|
| **US** | NCUA Supervisory Priorities | Cybersecurity controls, least privilege |
| **US** | FFIEC Cloud Guidance | Third-party risk, access controls |
| **Canada** | OSFI B-10, B-13, E-21 | Third-party risk, cyber risk, operational risk |
| **EU** | DORA (effective Jan 2025) | 4-hour incident reporting, ICT risk management |
| **EU** | EU AI Act | AI governance (Aug 2026) |

See [docs/COMPLIANCE-MAPPING.md](docs/COMPLIANCE-MAPPING.md) for detailed control mappings.

## Repository Structure

```
├── infrastructure/          # Terraform for AKS (K8s 1.34, Cilium, AzureLinux)
│   └── terraform/
├── tools/                   # Helm values and configurations
│   ├── falco/              # Runtime detection (0.43.0, modern_ebpf)
│   ├── falco-talon/        # Automated response (0.3.0)
│   ├── falcosidekick/      # Alert routing
│   ├── kyverno/            # Policy enforcement (1.17.0, VAP)
│   ├── kubescape/          # Compliance scanning (4.0.0, CIS-v1.12.0)
│   ├── trivy/              # Vulnerability scanning (0.29.0)
│   └── kubehound/          # Attack path analysis (1.6.7)
├── workloads/               # Vulnerable and compliant example apps
│   ├── vulnerable-app/     # Intentionally insecure for demo
│   └── compliant-app/      # Passes all Kyverno policies
├── scenarios/               # Demo scenarios (attack-detect-prevent)
│   └── attack-detect-prevent/  # Scripts and docs for MITRE ATT&CK demo
├── ci-cd/                   # Pipeline templates (Azure DevOps, GitHub Actions)
├── scripts/                 # Automation scripts
└── docs/                    # Documentation and compliance mappings
```

## Key Features

### Falco 0.43.0 with Modern eBPF
- Uses `modern_ebpf` driver (legacy eBPF deprecated)
- Custom financial services rules with MITRE ATT&CK tagging
- Integration with Falco Talon for automated response

### Falco Talon 0.3.0 (NEW)
- Automated threat response engine
- Network policy injection for pod isolation
- Pod labeling for forensic investigation
- Configurable response rules per threat type

### Kyverno 1.17.0 with VAP
- ValidatingAdmissionPolicy auto-generation for API server-level execution
- 6 policies (4 enforce, 2 audit) with regulatory annotations
- Namespace exclusions for system components

### Kubescape 4.0.0
- CIS Kubernetes Benchmark v1.12.0 (aligned with K8s 1.30+)
- NSA, MITRE, and SOC2 frameworks
- Continuous scanning with compliance trending

## Prerequisites

```bash
# Required tools
az --version      # Azure CLI (logged in)
terraform -v      # Terraform 1.5+
kubectl version   # kubectl
helm version      # Helm 3.x
docker --version  # Docker (for building demo images)
```

## Cleanup

```bash
# Reset for fresh demo run (keep cluster + tools, redeploy vulnerable app)
./scripts/cleanup.sh --reset-demo

# Remove demo workloads and policies only
./scripts/cleanup.sh

# Full teardown including Azure infrastructure
./scripts/cleanup.sh --full --destroy
```

## Webinar Recording

Watch the full webinar: [Link to recording]

## License

MIT License - See [LICENSE](LICENSE)

## Contributing

This is a demonstration repository. For production implementations, adapt the configurations to your specific requirements and security policies.

## Contact

Michael Forrester
Senior Principal Trainer & DevOps Advocate
KodeKloud
michael.forrester@kodekloud.com
