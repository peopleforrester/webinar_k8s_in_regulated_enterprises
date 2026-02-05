# Azure DevOps Pipeline Templates

Template pipelines for building, scanning, and deploying to AKS.
These are reference templates - adapt to your organization's requirements.

## Pipelines

| Pipeline | Purpose |
|----------|---------|
| build-pipeline.yaml | Build container images and push to ACR |
| security-scan-pipeline.yaml | Run Trivy scans on images before deployment |
| deploy-pipeline.yaml | Deploy to AKS with Kyverno policy pre-check |

## Usage

Import these pipeline templates into your Azure DevOps project and
configure the required variable groups and service connections.

## Required Variable Groups

- `aks-credentials` - Azure subscription and AKS cluster details
- `acr-credentials` - Azure Container Registry connection
