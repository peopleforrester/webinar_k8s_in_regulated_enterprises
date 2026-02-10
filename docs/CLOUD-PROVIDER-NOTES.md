<!-- ABOUTME: Skeleton document covering cloud provider differences for running -->
<!-- ABOUTME: the security tooling stack on AKS, EKS, and GKE clusters. -->

# Cloud Provider Notes

Brief intro: This repo targets AKS (Azure Kubernetes Service), but most tools work on any Kubernetes cluster. This document highlights key differences when running on EKS (AWS) or GKE (Google Cloud).

## General Differences

| Feature | AKS | EKS | GKE |
|---|---|---|---|
| Default CNI | Azure CNI | VPC CNI | GKE CNI (Dataplane V2) |
| Network Policy | Calico or Azure NPM | Calico | Dataplane V2 (native) |
| Ingress | Azure App Gateway / NGINX | AWS ALB | GKE Ingress |
| Secrets Integration | Azure Key Vault CSI | AWS Secrets Manager CSI | GCP Secret Manager CSI |
| Node Autoscaling | Cluster Autoscaler / Karpenter (preview) | Karpenter (GA) | GKE Autopilot / NAP |
| Service Mesh | Istio add-on (preview) | App Mesh / Istio | Anthos Service Mesh |
| Container Registry | ACR | ECR | Artifact Registry |

## Tool-Specific Notes

### Falco
- **AKS**: eBPF probe works on most AKS kernel versions. Use `driver.kind: modern_ebpf`.
- **EKS**: Works well. Bottlerocket nodes may need kernel module driver.
- **GKE**: COS (Container-Optimized OS) nodes require eBPF driver. Standard Ubuntu nodes support both.

### Kyverno
- No cloud-specific differences. Works identically across all providers.

### Trivy Operator
- No cloud-specific differences. Image pull credentials may need cloud-specific setup.

### Kubescape
- No cloud-specific differences. Host scanner findings may vary by node OS.

### Karpenter
- **AKS**: Preview support via AKS Karpenter Provider (aksNodeClass). Limited feature set.
- **EKS**: GA support. Full feature set with EC2NodeClass.
- **GKE**: Not applicable. Use GKE Node Auto-Provisioning instead.

### External Secrets
- **AKS**: Use AzureKeyVault provider with Managed Identity.
- **EKS**: Use AWS Secrets Manager or Parameter Store provider with IRSA.
- **GKE**: Use GCP Secret Manager provider with Workload Identity.

### Istio
- **AKS**: Available as AKS managed add-on (preview) or self-managed via Helm.
- **EKS**: Self-managed via Helm or use AWS App Mesh.
- **GKE**: Available as Anthos Service Mesh (managed) or self-managed.

### Harbor
- **AKS**: Integrate with Azure DNS and cert-manager for ingress.
- **EKS**: Integrate with Route53 and cert-manager.
- **GKE**: Integrate with Cloud DNS and cert-manager.

### Crossplane
- **AKS**: Use provider-azure for Azure resource provisioning.
- **EKS**: Use provider-aws for AWS resource provisioning.
- **GKE**: Use provider-gcp for GCP resource provisioning.

## Contributing Provider-Specific Notes

When adding a new tool, include an "EKS / GKE Notes" section in the tool's README. Focus on:
1. Driver or runtime differences (eBPF, CSI, etc.)
2. Authentication differences (Managed Identity vs IRSA vs Workload Identity)
3. Cloud-specific integrations (DNS, load balancers, registries)
4. Feature availability differences (GA vs preview)
