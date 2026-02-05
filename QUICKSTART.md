# Quick Start Guide

Deploy a fully secured AKS cluster with the complete CNCF security stack in 15 minutes.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Terraform >= 1.6.0
- kubectl >= 1.29
- Helm >= 3.14
- Docker (for KubeHound)

## Step 1: Deploy AKS Cluster (5 minutes)

```bash
cd infrastructure/terraform

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
# - Set your Azure subscription ID
# - Choose resource group name
# - Set location (e.g., eastus2)

# Initialize and apply
terraform init
terraform apply -auto-approve

# Get credentials
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw aks_cluster_name)

# Verify connection
kubectl get nodes
```

## Step 2: Install Security Tools (5 minutes)

```bash
cd ../../scripts
chmod +x *.sh

# Install all security tools
./install-security-tools.sh

# Verify installations
kubectl get pods -n falco
kubectl get pods -n kyverno
kubectl get pods -n trivy-system
kubectl get pods -n kubescape
```

## Step 3: Deploy Demo Workloads (2 minutes)

```bash
# Deploy the vulnerable application (before Kyverno policies)
kubectl apply -f ../demo-workloads/vulnerable-app/namespace.yaml
kubectl apply -f ../demo-workloads/vulnerable-app/

# Deploy the compliant application
kubectl apply -f ../demo-workloads/compliant-app/namespace.yaml
kubectl apply -f ../demo-workloads/compliant-app/
```

## Step 4: Run the Demo (3 minutes)

```bash
# Run the interactive demo script
./run-demo.sh

# Or run individual components:
# - Attack simulation
cd ../attack-simulation
./01-reconnaissance.sh

# - View Falco alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# - Apply Kyverno policies and test
kubectl apply -f ../security-tools/kyverno/policies/
kubectl apply -f ../demo-workloads/vulnerable-app/deployment.yaml
# (Should be rejected!)

# - Generate compliance report
./generate-compliance-report.sh
```

## Step 5: Cleanup

```bash
cd ../scripts
./cleanup.sh

# Or destroy everything
cd ../infrastructure/terraform
terraform destroy -auto-approve
```

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and solutions.
