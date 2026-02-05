#!/usr/bin/env bash
# Attack Simulation: Phase 1 - Reconnaissance
# Simulates an attacker who has gained access to a container and is
# performing initial reconnaissance of the Kubernetes environment.
#
# MITRE ATT&CK: T1046 (Network Service Discovery), T1083 (File and Directory Discovery)
# Falco rules triggered: Terminal Shell in Container, Read Service Account Token

set -euo pipefail

NAMESPACE="vulnerable-app"
APP_LABEL="app=vulnerable-app"
BOLD='\033[1m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Phase 1: Reconnaissance${NC}"
echo -e "${BOLD}  MITRE ATT&CK: T1046, T1083${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# Get the pod name
POD=$(kubectl get pod -n "${NAMESPACE}" -l "${APP_LABEL}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "${POD}" ]]; then
    echo -e "${RED}ERROR: No vulnerable-app pod found in namespace ${NAMESPACE}${NC}"
    echo "Deploy the vulnerable app first: kubectl apply -f ../demo-workloads/vulnerable-app/"
    exit 1
fi

echo -e "${GREEN}Target pod: ${POD}${NC}"
echo ""

# Step 1: Discover environment variables
echo -e "${YELLOW}[1/5] Discovering environment variables...${NC}"
echo -e "  Command: env | grep -i kube"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'env | grep -i kube || true'
echo ""
sleep 2

# Step 2: Read service account token
echo -e "${YELLOW}[2/5] Reading service account token... (triggers Falco)${NC}"
echo -e "  Command: cat /var/run/secrets/kubernetes.io/serviceaccount/token"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null | head -c 50; echo "..."'
echo ""
sleep 2

# Step 3: Discover service account namespace
echo -e "${YELLOW}[3/5] Reading service account namespace...${NC}"
echo -e "  Command: cat /var/run/secrets/kubernetes.io/serviceaccount/namespace"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'cat /var/run/secrets/kubernetes.io/serviceaccount/namespace'
echo ""
sleep 2

# Step 4: Scan for internal services
echo -e "${YELLOW}[4/5] Scanning for internal services...${NC}"
echo -e "  Command: cat /etc/resolv.conf"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'cat /etc/resolv.conf'
echo ""
sleep 2

# Step 5: Discover mounted filesystems and processes
echo -e "${YELLOW}[5/5] Discovering filesystem and processes...${NC}"
echo -e "  Command: mount | head -10"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'mount | head -10'
echo ""

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Reconnaissance Complete${NC}"
echo -e "${RED}  Check Falco logs for alerts!${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo -e "View Falco alerts: kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=2m"
