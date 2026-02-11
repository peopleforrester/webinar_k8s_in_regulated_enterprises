# Troubleshooting

Common issues and solutions when running the AKS regulated enterprise demo.

## Terraform Issues

### "Error: Provider not found"

```
terraform init
```

Run `terraform init` to download required providers.

### "Error: Subscription not found"

Verify you're logged into the correct Azure subscription:

```bash
az account show
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### "Error: Resource group already exists"

Change the `resource_group_name` in `terraform.tfvars` or import the existing resource:

```bash
terraform import azurerm_resource_group.main /subscriptions/SUB_ID/resourceGroups/RG_NAME
```

### AKS creation takes too long (>15 minutes)

AKS provisioning typically takes 5-10 minutes. If it exceeds 15 minutes:

```bash
# Check Azure status
az aks show --resource-group RG_NAME --name CLUSTER_NAME --query provisioningState
```

## Kubernetes Connection Issues

### "Unable to connect to the server"

```bash
# Re-fetch credentials
az aks get-credentials --resource-group RG_NAME --name CLUSTER_NAME --admin --overwrite-existing

# Verify context
kubectl config current-context
kubectl get nodes
```

### Nodes show "NotReady"

Wait 2-3 minutes after cluster creation. If nodes remain NotReady:

```bash
kubectl describe node NODE_NAME | grep -A 5 Conditions
```

## Security Tool Issues

### Falco pods in CrashLoopBackOff

The eBPF driver may not be compatible with your node OS. Try:

```bash
# Switch to modern_ebpf driver
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --set driver.kind=modern_ebpf \
  --reuse-values
```

### Falco not generating alerts

```bash
# Verify Falco is running
kubectl get pods -n falco

# Check Falco logs for errors
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50

# Verify custom rules are loaded
kubectl exec -n falco POD_NAME -- falco --list
```

### Kyverno policies not blocking

```bash
# Verify policies are in Enforce mode
kubectl get clusterpolicies -o custom-columns=NAME:.metadata.name,ACTION:.spec.validationFailureAction

# Check Kyverno controller logs
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller --tail=50

# Verify webhook is registered
kubectl get validatingwebhookconfigurations | grep kyverno
```

### Kyverno webhook timeout errors

```bash
# Restart Kyverno admission controller
kubectl rollout restart deployment -n kyverno kyverno-admission-controller

# If persistent, increase webhook timeout
kubectl edit validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg
# Set timeoutSeconds to 30
```

### Trivy Operator not scanning

```bash
# Check operator logs
kubectl logs -n trivy-system -l app.kubernetes.io/name=trivy-operator --tail=50

# Verify scan jobs
kubectl get jobs -n trivy-system

# Force a rescan
kubectl annotate pod POD_NAME -n NAMESPACE trivy-operator.aquasecurity.github.io/rescan=true
```

### Kubescape scan fails

```bash
# Verify Kubescape operator is running
kubectl get pods -n kubescape

# Run a local scan instead
kubescape scan framework nsa --verbose

# Check for RBAC issues
kubectl auth can-i list pods --as system:serviceaccount:kubescape:kubescape-scanner -A
```

## Tier 2 Tool Issues

### Prometheus Stack pods not starting

```bash
# Check all components
kubectl get pods -n monitoring

# Prometheus PVC issues (check StorageClass)
kubectl get pvc -n monitoring
kubectl describe pvc -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0

# Grafana not loading dashboards
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=50
```

### ArgoCD sync failures

```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# View sync details
kubectl describe application -n argocd APP_NAME

# Check server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50

# Get admin password
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### External Secrets Operator not syncing

```bash
# Check ClusterSecretStore status
kubectl get clustersecretstores
kubectl describe clustersecretstore azure-keyvault

# Check ExternalSecret status
kubectl get externalsecrets -A

# Verify workload identity
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50
```

## Tier 3 Tool Issues

### Istio istiod not starting

```bash
# Verify Istio CRDs installed (base chart)
kubectl get crds | grep istio

# Check istiod logs
kubectl logs -n istio-system -l app=istiod --tail=50

# Verify sidecar injection
kubectl get namespace -L istio-injection
```

### Istio sidecar not injecting

```bash
# Label the namespace for injection
kubectl label namespace TARGET_NS istio-injection=enabled

# Restart pods to trigger injection
kubectl rollout restart deployment -n TARGET_NS

# Verify sidecars
kubectl get pods -n TARGET_NS -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}'
```

### Crossplane provider not healthy

```bash
# Check provider status
kubectl get providers

# Check provider pod
kubectl get pods -n crossplane-system

# View provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision

# Verify ProviderConfig
kubectl get providerconfig
```

### Harbor pods not ready (allow 10+ minutes)

```bash
# Harbor has 7+ components — check all
kubectl get pods -n harbor

# Common issue: PVC not binding
kubectl get pvc -n harbor

# Verify StorageClass exists
kubectl get sc managed-csi-premium

# Check Harbor core logs
kubectl logs -n harbor -l component=core --tail=50
```

## Tier 4 Tool Issues

### Karpenter (NAP) not provisioning nodes

```bash
# Verify NAP is enabled
az aks show -g RG_NAME -n CLUSTER_NAME --query nodeProvisioningProfile

# Check NodePool and AKSNodeClass CRDs
kubectl get nodepools
kubectl get aksnodeclasses

# View Karpenter controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50
```

## Demo Workload Issues

### Vulnerable app fails to deploy (before policies)

If deploying before Kyverno policies and it still fails:

```bash
# Check namespace exists
kubectl get ns vulnerable-app

# Check for other admission controllers blocking
kubectl apply -f workloads/vulnerable-app/deployment.yaml --dry-run=server -v=5
```

### Compliant app pods crash

The compliant app uses non-root user and read-only rootfs. If pods crash:

```bash
# Check pod logs
kubectl logs -n compliant-app -l app=compliant-app

# Verify volumes are mounted correctly
kubectl describe pod -n compliant-app -l app=compliant-app | grep -A 10 Volumes
```

Common issue: nginx needs writable `/var/cache/nginx`, `/var/run`, and `/tmp`.
These should be mounted as emptyDir volumes.

## KubeHound Issues

### Docker compose fails to start

```bash
# Verify Docker is running
docker info

# Check port conflicts
lsof -i :8182  # JanusGraph
lsof -i :8183  # GraphExp UI

# View KubeHound logs
docker compose -f tools/kubehound/docker-compose.yaml logs
```

### KubeHound cannot access cluster

```bash
# Verify kubeconfig is accessible from Docker
ls -la ~/.kube/config

# Test with kubectl inside container
docker compose exec kubehound kubectl get nodes
```

## Performance Issues

### Falco consuming too many resources

```bash
# Check resource usage
kubectl top pods -n falco

# Reduce syscall monitoring scope
# Edit values.yaml to add more items to falco.rules_file exclusions
```

### Cluster running slow during demo

Consider reducing to a single replica for each security tool during the demo:

```bash
kubectl scale deployment -n kyverno kyverno-admission-controller --replicas=1
kubectl scale deployment -n kyverno kyverno-background-controller --replicas=1
```

## Test Suite

Run the built-in test framework to diagnose issues:

```bash
make test              # Unit tests (no cluster needed)
make test-integration  # Check all tool pods and endpoints
make test-e2e          # Full scenario validation
make test-all          # Everything
```

## Getting Help

- Falco: https://falco.org/docs/
- Kyverno: https://kyverno.io/docs/
- Trivy: https://aquasecurity.github.io/trivy/
- Kubescape: https://kubescape.io/docs/
- KubeHound: https://kubehound.io/
- Prometheus: https://prometheus.io/docs/
- ArgoCD: https://argo-cd.readthedocs.io/
- Istio: https://istio.io/latest/docs/
- Crossplane: https://docs.crossplane.io/
- Harbor: https://goharbor.io/docs/
- External Secrets: https://external-secrets.io/
- Karpenter: https://karpenter.sh/docs/
- AKS: https://learn.microsoft.com/en-us/azure/aks/
