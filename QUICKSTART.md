# Quick Start Guide

Deploy an AKS lab cluster, then pick any tool from the [Tool Catalog](README.md#tool-catalog) and follow its README.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Terraform >= 1.6.0
- kubectl >= 1.30
- Helm >= 3.14
- Docker (optional, for KubeHound)

## Three Paths

**Path A — Pick a tool:** Deploy the AKS cluster (Step 1), then `cd tools/<tool-name>` and follow that tool's README.

**Path B — Run the security demo:** Deploy the cluster (Step 1), install Tier 1 security tools (Step 2), deploy workloads (Step 3), and run the Attack → Detect → Prevent → Prove demo (Step 4).

**Path C — Full production stack:** Deploy the cluster (Step 1), install all tiers (Step 2b), then run any of the four scenarios (Step 4).

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
  --name $(terraform output -raw aks_cluster_name) \
  --admin

# Verify connection
kubectl get nodes
```

## Step 2: Install Tools

### Option A — Security tools only (5 minutes)

```bash
./scripts/install-tools.sh --tier=1
# or: make install-tier1

# Verify installations
kubectl get pods -n falco          # Falco + Falcosidekick + Talon
kubectl get pods -n kyverno        # Kyverno controllers
kubectl get pods -n trivy-system   # Trivy Operator
kubectl get pods -n kubescape      # Kubescape Operator
```

### Option B — Full production stack (15-20 minutes)

```bash
./scripts/install-tools.sh
# or: make install

# Verify all tiers
make test-integration
```

This installs all four tiers:
- **Tier 1** (Security): Falco, Falcosidekick, Falco Talon, Kyverno, Trivy, Kubescape
- **Tier 2** (Observability): Prometheus Stack (with Grafana), ArgoCD, External Secrets
- **Tier 3** (Platform): Istio, Crossplane, Harbor
- **Tier 4** (AKS-Managed): Karpenter Node Autoprovisioning

See [docs/INSTALL-ORDER.md](docs/INSTALL-ORDER.md) for the dependency graph.

## Step 3: Deploy Demo Workloads (2 minutes)

```bash
# Deploy the vulnerable application (demonstrates policy violations)
kubectl apply -f workloads/vulnerable-app/namespace.yaml
kubectl apply -f workloads/vulnerable-app/

# Deploy the compliant application (passes all policies)
kubectl apply -f workloads/compliant-app/namespace.yaml
kubectl apply -f workloads/compliant-app/
```

## Step 4: Run a Scenario

### Scenario 1: Attack, Detect, Prevent, Prove (Tier 1)

```bash
make demo-attack
# or: ./scenarios/attack-detect-prevent/run-demo.sh
```

Individual steps:
```bash
cd scenarios/attack-detect-prevent
./01-reconnaissance.sh        # Attack simulation
./02-credential-theft.sh      # Falco detects
./03-lateral-movement.sh      # Kyverno prevents
```

### Scenario 2: GitOps Delivery Pipeline (Tier 2)

```bash
make demo-gitops
# or: ./scenarios/gitops-delivery/run-demo.sh
```

### Scenario 3: Zero-Trust Networking (Tier 3)

```bash
make demo-zerotrust
# or: ./scenarios/zero-trust/run-demo.sh
```

### Scenario 4: FinOps Cost Optimization (Tier 4)

```bash
make demo-finops
# or: ./scenarios/finops/run-demo.sh
```

## Step 5: Cleanup

```bash
# Reset for a fresh demo (removes workloads/policies, redeploys vulnerable app)
./scripts/cleanup.sh --reset-demo

# Remove workloads and policies only (keep cluster + tools)
./scripts/cleanup.sh

# Remove workloads, policies, and security tools (keep cluster)
./scripts/cleanup.sh --full

# Destroy everything including AKS cluster
./scripts/cleanup.sh --full --destroy
```

## Key Demonstrations

### 1. KubeHound Attack Paths
```bash
cd tools/kubehound
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
