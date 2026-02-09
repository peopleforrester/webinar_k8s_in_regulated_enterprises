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

## Demo Workload Issues

### Vulnerable app fails to deploy (before policies)

If deploying before Kyverno policies and it still fails:

```bash
# Check namespace exists
kubectl get ns vulnerable-app

# Check for other admission controllers blocking
kubectl apply -f demo-workloads/vulnerable-app/deployment.yaml --dry-run=server -v=5
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
docker compose -f security-tools/kubehound/docker-compose.yaml logs
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

## Getting Help

- Falco: https://falco.org/docs/
- Kyverno: https://kyverno.io/docs/
- Trivy: https://aquasecurity.github.io/trivy/
- Kubescape: https://kubescape.io/docs/
- KubeHound: https://kubehound.io/
- AKS: https://learn.microsoft.com/en-us/azure/aks/
