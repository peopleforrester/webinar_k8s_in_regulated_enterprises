# Pre-Demo Testing Checklist

Use this checklist to validate every component before the Tuesday demo.

**Estimated time**: 45-60 minutes for full validation

---

## Phase 1: Prerequisites (5 min)

### Local Tools
```bash
# Run each command and verify output
az --version
# Expected: 2.50+ ✓

terraform -v
# Expected: 1.5+ ✓

kubectl version --client
# Expected: 1.30+ ✓

helm version
# Expected: 3.14+ ✓

docker --version
# Expected: 24+ ✓
```

- [ ] All tools installed at required versions
- [ ] `az login` completed successfully
- [ ] Correct Azure subscription selected (`az account show`)

### Azure Permissions
```bash
# Check you can create resources
az group create --name test-permissions-check --location eastus2
az group delete --name test-permissions-check --yes
```

- [ ] Can create resource groups
- [ ] No quota restrictions in target region

---

## Phase 2: Infrastructure Deployment (10-15 min)

### Terraform Init
```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
```

- [ ] `terraform init` succeeds
- [ ] Providers downloaded (azurerm, azuread, random)

### Terraform Plan
```bash
terraform plan -out=tfplan
```

- [ ] Plan completes without errors
- [ ] Resource count looks reasonable (~15-20 resources)
- [ ] No unexpected changes

### Terraform Apply
```bash
terraform apply tfplan
```

- [ ] Apply completes successfully
- [ ] Note actual time: ______ minutes
- [ ] All outputs displayed

### Cluster Connectivity
```bash
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw aks_cluster_name)

kubectl get nodes
```

- [ ] Credentials retrieved
- [ ] Nodes visible and Ready
- [ ] Node count matches config (system + user pools)

### Verify AKS Configuration
```bash
# Check Kubernetes version
kubectl version

# Check Cilium is running (not Azure NPM)
kubectl get pods -n kube-system | grep cilium

# Check node OS
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.osImage}'
```

- [ ] Kubernetes version is 1.34.x
- [ ] Cilium pods running (not azure-npm)
- [ ] Nodes running AzureLinux (CBL-Mariner)

---

## Phase 3: Security Tools Installation (10 min)

### Run Install Script
```bash
cd ../../scripts
./install-security-tools.sh
```

- [ ] Script completes without errors
- [ ] Note any warnings: _______________________

### Verify Falco
```bash
kubectl get pods -n falco
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=5
```

- [ ] Falco pod running
- [ ] Logs show "Falco initialized" or similar
- [ ] No driver errors (modern_ebpf should work on AzureLinux)

### Verify Falco Talon
```bash
kubectl get pods -n falco -l app.kubernetes.io/name=falco-talon
```

- [ ] Talon pod running
- [ ] Connected to Falco gRPC (check logs)

### Verify Kyverno
```bash
kubectl get pods -n kyverno
kubectl get clusterpolicies
```

- [ ] All Kyverno pods running (admission, background, cleanup, reports)
- [ ] 6 ClusterPolicies visible

### Verify Trivy
```bash
kubectl get pods -n trivy-system
```

- [ ] Trivy operator pod running

### Verify Kubescape
```bash
kubectl get pods -n kubescape
```

- [ ] Kubescape operator pod running

### Verify KubeHound (Local)
```bash
cd ../security-tools/kubehound
docker compose up -d
docker compose ps
```

- [ ] All 3 containers running (kubehound, janusgraph, graphexp)
- [ ] GraphExp UI accessible at http://localhost:8183

---

## Phase 4: Demo Workloads (5 min)

### Deploy Vulnerable App
```bash
kubectl apply -f demo-workloads/vulnerable-app/namespace.yaml
kubectl apply -f demo-workloads/vulnerable-app/
```

- [ ] Namespace created
- [ ] **EXPECTED**: Deployment should SUCCEED (policies not yet applied to this namespace)
- [ ] Pod running in vulnerable-app namespace

### Deploy Compliant App
```bash
kubectl apply -f demo-workloads/compliant-app/namespace.yaml
kubectl apply -f demo-workloads/compliant-app/
```

- [ ] Namespace created
- [ ] Deployment succeeds
- [ ] Pod running in compliant-app namespace

### Verify Apps Accessible
```bash
kubectl port-forward -n vulnerable-app svc/vulnerable-app 8081:80 &
kubectl port-forward -n compliant-app svc/compliant-app 8082:80 &
curl http://localhost:8081
curl http://localhost:8082
```

- [ ] Vulnerable app responds
- [ ] Compliant app responds

---

## Phase 5: Attack Simulation Testing (10 min)

### Reconnaissance
```bash
cd attack-simulation
./01-reconnaissance.sh
```

- [ ] Script runs without errors
- [ ] Check Falco logs for alerts:
```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep -i "reconnaissance\|secret\|token"
```
- [ ] Falco detected the activity

### Credential Theft
```bash
./02-credential-theft.sh
```

- [ ] Script runs
- [ ] Falco alerts on service account token read
- [ ] Check Talon response:
```bash
kubectl get pods -n vulnerable-app --show-labels | grep security.falco
```
- [ ] Pod labeled by Talon (if configured)

### Lateral Movement
```bash
./03-lateral-movement.sh
```

- [ ] Script runs
- [ ] Falco alerts generated

---

## Phase 6: Policy Enforcement Testing (5 min)

### Apply Kyverno Policies to Vulnerable Namespace
```bash
# First, remove the vulnerable deployment
kubectl delete deployment vulnerable-app -n vulnerable-app

# Try to redeploy (should FAIL now)
kubectl apply -f demo-workloads/vulnerable-app/deployment.yaml
```

- [ ] **EXPECTED ERROR**: "Privileged containers are not allowed"
- [ ] Policy enforcement working

### Test Each Policy
```bash
# Test privileged container block
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged
  namespace: default
spec:
  containers:
  - name: test
    image: nginx:1.25
    securityContext:
      privileged: true
EOF
```

- [ ] Rejected by disallow-privileged-containers policy

```bash
# Test latest tag block
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-latest
  namespace: default
spec:
  containers:
  - name: test
    image: nginx:latest
EOF
```

- [ ] Rejected by disallow-latest-tag policy

```bash
# Test run-as-root block
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-root
  namespace: default
spec:
  containers:
  - name: test
    image: nginx:1.25
    securityContext:
      runAsNonRoot: false
EOF
```

- [ ] Rejected by require-run-as-nonroot policy

---

## Phase 7: Compliance Reporting (5 min)

### Generate Report
```bash
cd ../scripts
./generate-compliance-report.sh
```

- [ ] Script completes
- [ ] Report generated

### Run Kubescape Scan
```bash
# If kubescape CLI installed locally:
kubescape scan framework nsa,cis-v1.12.0 --submit

# Or check operator results:
kubectl get vulnerabilitymanifests -A
```

- [ ] Scan completes
- [ ] Compliance score visible
- [ ] Note scores: NSA: ___% | CIS: ___% | SOC2: ___%

---

## Phase 8: KubeHound Attack Paths (5 min)

### Ingest Cluster Data
```bash
cd ../security-tools/kubehound
docker compose exec kubehound kubehound
```

- [ ] Ingestion completes without errors
- [ ] Nodes, pods, service accounts ingested

### Run Attack Path Query
```bash
docker compose exec kubehound kubehound query --file /queries/attack-paths.cypher
```

- [ ] Query returns results
- [ ] Attack paths visible

### Check Graph UI
- Open http://localhost:8183

- [ ] Graph visualization loads
- [ ] Can see nodes and relationships

---

## Phase 9: Full Demo Run-Through (10 min)

```bash
./scripts/run-demo.sh
```

Run through the complete demo script and note any issues:

- [ ] SEE phase (KubeHound) works
- [ ] DETECT phase (Falco alerts) works
- [ ] PREVENT phase (Kyverno blocks) works
- [ ] PROVE phase (Kubescape scores) works

### Issues Found
1. _________________________________________________
2. _________________________________________________
3. _________________________________________________

---

## Phase 10: Cleanup Verification

```bash
./scripts/cleanup.sh
```

- [ ] Workloads removed
- [ ] Tools uninstalled (optional)

### Full Destroy (After Testing)
```bash
cd infrastructure/terraform
terraform destroy
```

- [ ] All resources destroyed
- [ ] No orphaned resources in Azure portal

---

## Final Checklist

- [ ] All phases completed
- [ ] All critical items passing
- [ ] Issues documented and fixed
- [ ] Confident for Tuesday demo

### Notes for Demo Day
_________________________________________________
_________________________________________________
_________________________________________________

### Backup Plan
If something fails during the live demo:
1. Have screenshots/recordings ready
2. Pre-record the attack simulation section
3. Know which parts can be skipped
4. Have the compliance report pre-generated
