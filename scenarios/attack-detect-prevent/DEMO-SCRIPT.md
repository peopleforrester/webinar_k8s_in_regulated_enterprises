# Demo Script

Exact commands and talking points for the 20-minute live demo.

## Two Ways to Run the Demo

| Method | Command | Best for |
|--------|---------|----------|
| **Automated** | `./scripts/run-demo.sh` | Guided walkthrough with pauses for talking points |
| **Manual** | Follow the commands below | Full control over pacing and command order |

The automated script (`run-demo.sh`) handles deploying the vulnerable app, running attacks, applying policies, and scanning — all with interactive pauses. If you prefer to type commands live, follow the manual steps below.

## Setup (Before the Webinar)

Run these steps **30 minutes before** the webinar starts:

```bash
# 1. Deploy AKS cluster + install security tools (~15 min)
./scripts/full-demo-test.sh

# 2. Reset to a clean demo state (~2 min)
#    This removes policies/workloads from the test run,
#    then redeploys the vulnerable app so the demo starts fresh
./scripts/cleanup.sh --reset-demo

# 3. Verify everything is ready
kubectl get nodes                              # Cluster is up
kubectl get pods -n falco                      # Falco is watching
kubectl get pods -n kyverno                    # Kyverno engine is running (no policies active)
kubectl get pods -n vulnerable-app             # Vulnerable app is running
kubectl get clusterpolicies                    # Should return "No resources found"
```

## Pre-Demo Checklist

- [ ] AKS cluster deployed and `kubectl get nodes` shows Ready
- [ ] Security tools installed (Falco, Kyverno engine, Kubescape, Trivy)
- [ ] Demo reset completed (`./scripts/cleanup.sh --reset-demo`)
- [ ] Vulnerable app running (`kubectl get pods -n vulnerable-app`)
- [ ] No Kyverno policies active (`kubectl get clusterpolicies` returns empty)
- [ ] Two terminal windows open (one for commands, one for Falco logs)
- [ ] KubeHound running (if using attack path visualization)

---

## Part 1: ATTACK - Attack Path Analysis (5 minutes)

**Talking point:** "Before we fix anything, let's see how an attacker views this cluster."

### Show the vulnerable app configuration

```bash
# Show the deployment - highlight security violations
kubectl get deployment vulnerable-app -n vulnerable-app -o yaml | grep -A 5 securityContext
```

**Expected output:** Shows privileged: true, runAsUser: 0

### Show the overpermissioned service account

```bash
# Show the ClusterRole
kubectl get clusterrole vulnerable-app-role -o yaml
```

**Talking point:** "This service account can read secrets across every namespace."

### KubeHound attack paths (if running)

```bash
cd tools/kubehound
docker compose exec kubehound kubehound query --file /queries/attack-paths.cypher
```

**Talking point:** "KubeHound found X paths from this pod to cluster-admin. An attacker only needs one."

**Timing:** 5 minutes total

---

## Part 2: DETECT - Runtime Threat Detection (7 minutes)

**Talking point:** "Now let's simulate what happens when an attacker gets into this container."

### Start Falco log monitoring

```bash
# In terminal 2
kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=1m
```

### Run reconnaissance

```bash
# In terminal 1
./scenarios/attack-detect-prevent/01-reconnaissance.sh
```

**Talking point:** "Falco detected the service account token read. Every alert includes MITRE ATT&CK technique IDs."

### Run credential theft

```bash
./scenarios/attack-detect-prevent/02-credential-theft.sh
```

**Talking point:** "This is a CRITICAL alert - the container is querying the Kubernetes secrets API. In a financial services environment, this could mean access to database credentials, API keys, or customer data."

### Run lateral movement

```bash
./scenarios/attack-detect-prevent/03-lateral-movement.sh
```

**Talking point:** "Falco caught the privilege escalation attempt and the suspicious outbound connection. These alerts flow through Falcosidekick to your SIEM, Slack, or PagerDuty."

**Timing:** 7 minutes total (12 minutes cumulative)

---

## Part 3: PREVENT - Policy Enforcement (8 minutes)

**Talking point:** "Detection is essential, but prevention is better. Let's apply Kyverno policies."

### Apply Kyverno policies

```bash
kubectl apply -k tools/kyverno/policies/
kubectl get clusterpolicies
```

**Expected output:** 6 policies (4 Enforce, 2 Audit)

**Talking point:** "Each policy maps to a specific regulatory requirement - NCUA, OSFI, and DORA."

### Show a policy's regulatory mapping

```bash
kubectl get clusterpolicy disallow-privileged-containers -o yaml | head -20
```

**Talking point:** "The annotations tie this technical control directly to regulatory requirements your auditors care about."

### Try to redeploy the vulnerable app

```bash
kubectl delete deployment vulnerable-app -n vulnerable-app
kubectl apply -f workloads/vulnerable-app/deployment.yaml
```

**Expected output:** ERROR - blocked by Kyverno with clear message about which policies failed

**Talking point:** "Kyverno blocked this deployment at admission. It never runs. The error message tells the developer exactly what to fix."

### Deploy the compliant app

```bash
kubectl apply -f workloads/compliant-app/namespace.yaml
kubectl apply -f workloads/compliant-app/
kubectl get pods -n compliant-app
```

**Expected output:** Pods running successfully

**Talking point:** "Same nginx, but configured correctly. Non-root, read-only filesystem, resource limits, network policy. This passes all 6 policies."

### Show the difference

```bash
# Side by side comparison
diff <(kubectl get deploy vulnerable-app -n vulnerable-app -o yaml 2>/dev/null || echo "BLOCKED") \
     <(kubectl get deploy compliant-app -n compliant-app -o yaml)
```

**Timing:** 8 minutes total (20 minutes cumulative)

---

## Finale: PROVE - Compliance Posture

**Talking point:** "Finally, let's prove our compliance posture improved."

### Run Kubescape scan

```bash
# If kubescape CLI is available
kubescape scan framework nsa --include-namespaces compliant-app

# Or use the in-cluster operator
kubectl get workloadconfigurationscans -n compliant-app
```

**Talking point:** "Before our policies: roughly 67% compliance. After: 94%. These reports are your audit evidence."

### Show Trivy vulnerability reports

```bash
kubectl get vulnerabilityreports -n compliant-app
```

**Talking point:** "Trivy continuously scans every image and generates SBOMs - Software Bill of Materials - for supply chain compliance under DORA Article 28."

---

## Closing (30 seconds)

**Key messages:**
1. All 6 tools are CNCF/open source projects
2. Everything you saw deploys in 15 minutes from this repo
3. The demo maps to real regulatory frameworks (NCUA, OSFI, DORA)
4. Clone the repo and try it yourself

```
github.com/peopleforrester/webinar_k8s_in_regulated_enterprises
```

## After the Webinar

```bash
# Destroy everything to stop costs
./scripts/cleanup.sh --full --destroy
```
