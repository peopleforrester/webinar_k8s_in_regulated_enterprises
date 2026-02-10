#!/usr/bin/env bash
# ============================================================================
# ABOUTME: Attack simulation Phase 1 - Initial reconnaissance from compromised container.
# ABOUTME: Demonstrates MITRE ATT&CK techniques T1046 and T1083 with Falco detection.
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
#   Simulate the RECONNAISSANCE phase of an attack where an adversary has
#   gained initial access to a container (via RCE vulnerability, supply
#   chain compromise, or stolen credentials) and is now exploring the
#   environment to understand what they can access.
#
# ATTACK SCENARIO:
#   An attacker has compromised the vulnerable-app container through an
#   application vulnerability. They are now:
#   1. Discovering their environment (what cluster, what permissions)
#   2. Finding credentials (service account tokens)
#   3. Mapping the network (DNS, services)
#   4. Understanding the filesystem (mounted secrets, configs)
#
# ============================================================================
# MITRE ATT&CK MAPPING
# ============================================================================
#
# T1046 - Network Service Discovery
#   Tactic: Discovery
#   Description: Adversaries may attempt to get a listing of services running
#                on remote hosts, including those that may be vulnerable to
#                remote software exploitation.
#   In Kubernetes: Querying DNS, scanning service IPs, reading /etc/resolv.conf
#   Detection: Unusual network scanning, DNS queries for service discovery
#
# T1083 - File and Directory Discovery
#   Tactic: Discovery
#   Description: Adversaries may enumerate files and directories to find
#                information about the environment and identify targets.
#   In Kubernetes: Reading /proc, mounted secrets, environment files
#   Detection: Accessing sensitive paths like /var/run/secrets
#
# T1552.001 - Unsecured Credentials: Credentials in Files
#   Tactic: Credential Access
#   Description: Adversaries may search local file systems for files
#                containing credentials.
#   In Kubernetes: Service account tokens, mounted secrets
#   Detection: Reading service account token files
#
# ============================================================================
# FALCO RULES TRIGGERED
# ============================================================================
#
# The following Falco rules should detect this attack:
#
# 1. "Terminal Shell in Container"
#    - Priority: NOTICE
#    - Triggers: When an interactive shell is spawned in a container
#    - Why: Legitimate containers rarely need interactive shells
#
# 2. "Read Sensitive File Untrusted"
#    - Priority: WARNING
#    - Triggers: Reading service account tokens
#    - Why: Tokens are credentials that should only be read by the app
#
# 3. "Read Secret File from Non-Expected Program"
#    - Priority: WARNING
#    - Triggers: Non-standard programs reading secret paths
#    - Why: Only specific processes should access secrets
#
# 4. "Contact K8s API Server From Container"
#    - Priority: NOTICE
#    - Triggers: Direct API server contact (later phases)
#    - Why: Apps should use libraries, not raw API calls
#
# ============================================================================
# DETECTION INDICATORS
# ============================================================================
#
# Security teams should look for:
#   - Shell processes in containers (sh, bash, dash)
#   - Reads from /var/run/secrets/kubernetes.io/serviceaccount/
#   - Environment variable enumeration (env, printenv)
#   - DNS queries for kubernetes.default.svc
#   - Reads from /proc filesystem
#   - Mount point enumeration
#
# ============================================================================
# SAFETY NOTES
# ============================================================================
#
# This script:
#   - Only runs inside the vulnerable-app container
#   - Does not modify any files
#   - Does not exfiltrate any data
#   - Is designed to trigger detection, not cause harm
#   - Should only be run in isolated demo environments
#
# ============================================================================

set -euo pipefail

# Configuration
NAMESPACE="vulnerable-app"
APP_LABEL="app=vulnerable-app"

# Terminal colors for output formatting
BOLD='\033[1m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# ============================================================================
# SCRIPT HEADER
# ============================================================================
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Phase 1: Reconnaissance${NC}"
echo -e "${BOLD}  MITRE ATT&CK: T1046, T1083${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# ============================================================================
# TARGET POD IDENTIFICATION
# ============================================================================
# Before running commands, we need to identify the target pod. In a real
# attack, the attacker is already inside the container. Here, we use
# kubectl exec to simulate that access.
#
# The JSONPath query extracts just the pod name from the first matching pod.
# ============================================================================
POD=$(kubectl get pod -n "${NAMESPACE}" -l "${APP_LABEL}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "${POD}" ]]; then
    echo -e "${RED}ERROR: No vulnerable-app pod found in namespace ${NAMESPACE}${NC}"
    echo "Deploy the vulnerable app first: kubectl apply -f ../../workloads/vulnerable-app/"
    exit 1
fi

echo -e "${GREEN}Target pod: ${POD}${NC}"
echo ""

# ============================================================================
# STEP 1: ENVIRONMENT VARIABLE DISCOVERY
# ============================================================================
# TECHNIQUE: T1082 - System Information Discovery
#
# WHAT THE ATTACKER LEARNS:
#   - KUBERNETES_SERVICE_HOST: API server IP address
#   - KUBERNETES_SERVICE_PORT: API server port
#   - KUBERNETES_PORT_*: Additional service information
#   - Pod IP, namespace, and service account info
#
# WHY THIS MATTERS:
#   Environment variables reveal the Kubernetes infrastructure, including
#   how to reach the API server. This is the first step toward more
#   sophisticated API-based attacks.
#
# DETECTION:
#   This step is HARD to detect reliably because reading environment
#   variables is a normal application behavior. However, the pattern
#   of reconnaissance (env + token reading + API calls) is suspicious.
# ============================================================================
echo -e "${YELLOW}[1/5] Discovering environment variables...${NC}"
echo -e "  Command: env | grep -i kube"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'env | grep -i kube || true'
echo ""
sleep 2  # Pause between steps for demonstration

# ============================================================================
# STEP 2: SERVICE ACCOUNT TOKEN ACCESS
# ============================================================================
# TECHNIQUE: T1552.001 - Unsecured Credentials: Credentials in Files
#
# WHAT THE ATTACKER LEARNS:
#   - JWT token for authenticating to Kubernetes API
#   - Token encodes: service account name, namespace, expiration
#   - Can be used to make API calls with service account's permissions
#
# WHY THIS IS CRITICAL:
#   The service account token is the "keys to the kingdom" in Kubernetes.
#   With this token, an attacker can make API calls with whatever
#   permissions the service account has been granted.
#
# FALCO DETECTION:
#   Rule: "Read Sensitive File Untrusted"
#   Priority: WARNING
#   Output: Includes the process reading the file and the file path
#
# MITIGATION:
#   - Use short-lived tokens (TokenRequest API)
#   - Disable automounting (automountServiceAccountToken: false)
#   - Use minimal RBAC permissions
# ============================================================================
echo -e "${YELLOW}[2/5] Reading service account token... (triggers Falco)${NC}"
echo -e "  Command: cat /var/run/secrets/kubernetes.io/serviceaccount/token"
echo ""
# We only show first 50 chars to avoid exposing full token
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null | head -c 50; echo "..."'
echo ""
sleep 2

# ============================================================================
# STEP 3: NAMESPACE DISCOVERY
# ============================================================================
# TECHNIQUE: T1082 - System Information Discovery
#
# WHAT THE ATTACKER LEARNS:
#   - Current namespace (scopes API calls)
#   - Understanding of cluster organization
#
# WHY THIS MATTERS:
#   Knowing the namespace helps the attacker:
#   - Scope their API queries
#   - Understand the application context
#   - Identify potential targets in the same namespace
#
# This file is less sensitive than the token, but is part of the
# reconnaissance pattern that should raise suspicion.
# ============================================================================
echo -e "${YELLOW}[3/5] Reading service account namespace...${NC}"
echo -e "  Command: cat /var/run/secrets/kubernetes.io/serviceaccount/namespace"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'cat /var/run/secrets/kubernetes.io/serviceaccount/namespace'
echo ""
sleep 2

# ============================================================================
# STEP 4: DNS AND NETWORK DISCOVERY
# ============================================================================
# TECHNIQUE: T1046 - Network Service Discovery
#
# WHAT THE ATTACKER LEARNS:
#   - DNS server (usually CoreDNS in cluster)
#   - Search domains (reveals cluster domain name)
#   - How to resolve Kubernetes service names
#
# WHY THIS MATTERS:
#   With DNS information, the attacker can:
#   - Discover other services (nslookup *.default.svc.cluster.local)
#   - Find databases, caches, and other infrastructure
#   - Plan lateral movement
#
# DETECTION:
#   - Unusual DNS queries for service discovery
#   - Queries for many different services
#   - DNS zone transfer attempts
# ============================================================================
echo -e "${YELLOW}[4/5] Scanning for internal services...${NC}"
echo -e "  Command: cat /etc/resolv.conf"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'cat /etc/resolv.conf'
echo ""
sleep 2

# ============================================================================
# STEP 5: FILESYSTEM AND MOUNT DISCOVERY
# ============================================================================
# TECHNIQUE: T1083 - File and Directory Discovery
#
# WHAT THE ATTACKER LEARNS:
#   - What filesystems are mounted (secrets, configmaps)
#   - If the root filesystem is read-only
#   - What host paths might be exposed
#   - Container runtime type (containerd, docker)
#
# WHY THIS MATTERS:
#   Mount information reveals:
#   - Where secrets are located
#   - If host filesystem is accessible (container escape vector)
#   - What writable paths exist
#   - Potential persistence locations
#
# SECURITY BEST PRACTICE:
#   - Use read-only root filesystem
#   - Minimize mounted volumes
#   - Never mount host paths unless absolutely necessary
# ============================================================================
echo -e "${YELLOW}[5/5] Discovering filesystem and processes...${NC}"
echo -e "  Command: mount | head -10"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'mount | head -10'
echo ""

# ============================================================================
# RECONNAISSANCE SUMMARY
# ============================================================================
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Reconnaissance Complete${NC}"
echo -e "${RED}  Check Falco logs for alerts!${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo -e "View Falco alerts: kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=2m"
