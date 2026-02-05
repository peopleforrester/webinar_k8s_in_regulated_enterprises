# AKS Regulated Enterprise Demo

> Companion repository for the KodeKloud webinar "AKS for Regulated Enterprise in the Age of AI"

## What This Repository Demonstrates

This repository provides a complete, deployable example of securing Azure Kubernetes Service (AKS) for regulated financial services environments using CNCF open source tools.

**The Security Stack:**
- **KubeHound** - Attack path analysis and visualization
- **Falco** - Runtime threat detection (CNCF Graduated)
- **Kyverno** - Policy-as-code enforcement (CNCF Incubating)
- **Trivy** - Vulnerability scanning and SBOM generation
- **Kubescape** - Compliance posture management (CNCF Incubating)

## Quick Start (15 minutes)

See [QUICKSTART.md](QUICKSTART.md) for step-by-step deployment instructions.

```bash
# Clone the repository
git clone https://github.com/kodekloud/nfcu-aks-regulated-demo.git
cd nfcu-aks-regulated-demo

# Deploy infrastructure (requires Azure CLI authenticated)
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply

# Install security tools
cd ../../scripts
./install-security-tools.sh

# Run the demo
./run-demo.sh
```

## Regulatory Compliance Mapping

This demo addresses requirements from:
- **US**: NCUA supervisory priorities, FFIEC cloud guidance
- **Canada**: OSFI B-10 (Third-Party Risk), B-13 (Cyber Risk), E-23 (Model Risk)
- **EU**: DORA (Digital Operational Resilience Act), EU AI Act

See [docs/COMPLIANCE-MAPPING.md](docs/COMPLIANCE-MAPPING.md) for detailed control mappings.

## Repository Structure

```
├── infrastructure/      # Terraform for AKS cluster
├── security-tools/      # Helm values and configurations
├── demo-workloads/      # Vulnerable and compliant example apps
├── attack-simulation/   # Scripts to demonstrate attacks
├── ci-cd/              # Pipeline templates
├── scripts/            # Automation scripts
└── docs/               # Documentation and diagrams
```

## Security Tools Versions (February 2026)

| Tool | Version | Helm Chart |
|------|---------|------------|
| Falco | 0.42.x | falcosecurity/falco |
| Falcosidekick | 2.30.x | falcosecurity/falcosidekick |
| Kyverno | 1.16.x | kyverno/kyverno |
| Trivy Operator | 0.31.x | aqua/trivy-operator |
| Kubescape | 3.x | kubescape/kubescape-operator |
| KubeHound | 1.5.x | Manual deployment |

## Webinar Recording

Watch the full webinar: [Link to recording]

## License

MIT License - See [LICENSE](LICENSE)

## Contributing

This is a demonstration repository. For production implementations, please adapt the configurations to your specific requirements.

## Contact

Michael Forrester
Senior Principal Trainer & DevOps Advocate
KodeKloud
michael.forrester@kodekloud.com
