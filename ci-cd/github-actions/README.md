# GitHub Actions Workflow Templates

Template workflows for building, scanning, and deploying to AKS.
These are reference templates - adapt to your organization's requirements.

## Workflows

| Workflow | Purpose |
|----------|---------|
| build.yaml | Build container images and push to ACR |
| security-scan.yaml | Run Trivy and Kubescape scans |
| deploy.yaml | Deploy to AKS with policy pre-check |
| compliance-report.yaml | Generate weekly compliance reports |

## Required Secrets

Configure these in your GitHub repository settings:

- `AZURE_CREDENTIALS` - Azure service principal JSON
- `ACR_LOGIN_SERVER` - ACR login server URL
- `ACR_USERNAME` - ACR username
- `ACR_PASSWORD` - ACR password
- `AKS_CLUSTER_NAME` - AKS cluster name
- `AKS_RESOURCE_GROUP` - AKS resource group name
