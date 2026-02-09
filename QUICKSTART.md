# Quick Start Guide

Deploy a fully secured AKS cluster with the complete CNCF security stack in 15 minutes.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Terraform >= 1.6.0
- kubectl >= 1.30
- Helm >= 3.14
- Docker (for KubeHound)

## What Gets Deployed

| Component | Version | Description |
|-----------|---------|-------------|
| AKS | Kubernetes 1.34 | With Cilium, AzureLinux, Image Cleaner |
| Falco | 0.43.0 | Runtime detection (modern_ebpf) |
| Falco Talon | 0.3.0 | Automated threat response |
| Kyverno | 1.17.0 | Policy enforcement (VAP enabled) |
| Kubescape | 4.0.0 | Compliance scanning (CIS-v1.12.0) |
| Trivy | 0.29.0 | Vulnerability scanning |
| KubeHound | 1.6.7 | Attack path analysis |

## Automated Full Test (Recommended)

Run the complete end-to-end test with a single command:

```bash
# Full test: deploy infra + install tools + run demo + validate
./scripts/full-demo-test.sh

# Skip infrastructure (use existing cluster)
./scripts/full-demo-test.sh --skip-infra

# Quick validation of existing setup
./scripts/quick-validate.sh

# Cleanup only
./scripts/full-demo-test.sh --cleanup-only
```

**What `full-demo-test.sh` does:**
1. Checks prerequisites (az, terraform, kubectl, helm, kubescape, trivy)
2. Deploys AKS infrastructure via Terraform
3. Installs Kyverno, Falco, and Kubescape
4. Deploys compliant app, tests that vulnerable app is blocked
5. Runs attack simulation to generate Falco alerts
6. Runs Kubescape and Trivy compliance scans
7. Displays validation summary
8. Optionally cleans up infrastructure

**Estimated time:** 15-20 minutes
**Estimated cost:** ~$10-15 for a 1-hour test

---

## Step 1: Deploy AKS Cluster (5-10 minutes)

```bash
# Use the setup script (recommended)
./scripts/setup-cluster.sh

# Or manually:
cd infrastructure/terraform

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
# - Set your Azure subscription ID
# - Choose resource group name
# - Set location (e.g., eastus2)

# Initialize and apply
terraform init
terraform apply

# Get credentials
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw aks_cluster_name)

# Verify connection
kubectl get nodes
```

## Step 2: Install Security Tools (5 minutes)

```bash
./scripts/install-security-tools.sh

# Verify installations
kubectl get pods -n falco          # Falco + Talon
kubectl get pods -n kyverno        # Kyverno controllers
kubectl get pods -n trivy-system   # Trivy Operator
kubectl get pods -n kubescape      # Kubescape Operator
```

## Step 3: Deploy Demo Workloads (2 minutes)

```bash
# Deploy the vulnerable application (demonstrates policy violations)
kubectl apply -f demo-workloads/vulnerable-app/namespace.yaml
kubectl apply -f demo-workloads/vulnerable-app/

# Deploy the compliant application (passes all policies)
kubectl apply -f demo-workloads/compliant-app/namespace.yaml
kubectl apply -f demo-workloads/compliant-app/
```

## Step 4: Run the Demo

```bash
# Run the interactive demo script
./scripts/run-demo.sh
```

### Or run individual components:

**Attack Simulation (SEE phase)**
```bash
cd attack-simulation
./01-reconnaissance.sh
./02-credential-theft.sh
./03-lateral-movement.sh
```

**View Falco Alerts (DETECT phase)**
```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -f
```

**Test Kyverno Policies (PREVENT phase)**
```bash
# Apply policies
kubectl apply -f security-tools/kyverno/policies/

# Try to deploy vulnerable app (should be rejected!)
kubectl apply -f demo-workloads/vulnerable-app/deployment.yaml
# Error: Privileged containers are not allowed...
```

**Generate Compliance Report (PROVE phase)**
```bash
./scripts/generate-compliance-report.sh
```

## Step 5: Cleanup

```bash
# Remove workloads and tools (keep cluster)
./scripts/cleanup.sh

# Or destroy everything including AKS
cd infrastructure/terraform
terraform destroy
```

## Key Demonstrations

### 1. KubeHound Attack Paths
```bash
cd security-tools/kubehound
docker compose up -d
docker compose exec kubehound kubehound
# Open http://localhost:8183 for graph visualization
```

### 2. Falco + Talon Automated Response
```bash
# Simulate attack
kubectl exec -it -n vulnerable-app deploy/vulnerable-app -- sh -c "cat /var/run/secrets/kubernetes.io/serviceaccount/token"

# Watch Falco detect it
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=10

# Talon automatically labels the pod for investigation
kubectl get pods -n vulnerable-app --show-labels
```

### 3. Kyverno Policy Enforcement
```bash
# See which policies are active
kubectl get clusterpolicies

# Check policy reports
kubectl get policyreport -A
```

### 4. Kubescape Compliance Scan
```bash
# Run on-demand scan
kubescape scan framework nsa,cis-v1.12.0 --submit

# View results
kubectl get vulnerabilitymanifests -A
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Terraform fails on network | Ensure Cilium pod_cidr doesn't overlap with VNet |
| Falco pods CrashLooping | Check node OS - requires AzureLinux or Ubuntu |
| Kyverno blocking system pods | Namespace exclusions should be in place |
| KubeHound can't connect | Ensure kubeconfig is valid: `kubectl get nodes` |

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more solutions.
