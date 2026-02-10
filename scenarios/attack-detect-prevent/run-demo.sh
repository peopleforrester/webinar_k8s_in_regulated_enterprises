#!/usr/bin/env bash
# ============================================================================
# ABOUTME: Interactive demonstration script for the security webinar.
# ABOUTME: Walks through Attack -> Detect -> Prevent -> Prove narrative.
# ============================================================================
#
# PURPOSE:
#   This script provides a guided, interactive walkthrough of a complete
#   cloud-native security stack. It's designed for a 20-minute live demo
#   that tells a compelling story:
#
#   1. ATTACK  - Show how attackers see your cluster (KubeHound)
#   2. DETECT  - Catch attacks as they happen (Falco)
#   3. PREVENT - Block bad deployments at admission (Kyverno)
#   4. PROVE   - Demonstrate compliance improvement (Kubescape)
#
# TARGET AUDIENCE:
#   - Credit Union CTOs and security leaders
#   - Compliance officers (NCUA, OSFI, DORA)
#   - Platform engineering teams
#
# PREREQUISITES:
#   - AKS cluster deployed (setup-cluster.sh)
#   - Security tools installed (install-tools.sh)
#   - Demo workloads available in ../../workloads/
#
# USAGE:
#   ./run-demo.sh
#
#   The script pauses after each section for discussion. Press Enter
#   to advance to the next section.
#
# TIMING (approximate):
#   - Setup: 2 minutes
#   - Attack (KubeHound): 5 minutes
#   - Detect (Falco): 7 minutes
#   - Prevent (Kyverno): 8 minutes
#   - Prove (Kubescape): 3 minutes
#
# DEMO TIPS:
#   - Have a second terminal showing Falco logs
#   - Have KubeHound UI open in browser
#   - Practice the timing beforehand
#   - Know the "why" behind each step
#
# STORY ARC:
#   We deploy a vulnerable application that an attacker has compromised.
#   We show what the attacker can do, how Falco catches them, how Kyverno
#   would have prevented the vulnerable deployment, and how Kubescape
#   proves our improved security posture.
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."

# Terminal colors including BLUE for pause prompts
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ----------------------------------------------------------------------------
# HELPER FUNCTIONS
# ----------------------------------------------------------------------------

# Pause for presenter to discuss the current topic
# The blue color distinguishes prompts from command output
pause() {
    echo ""
    echo -e "${BLUE}  Press Enter to continue...${NC}"
    read -r
}

# Display section headers with consistent formatting
# Makes it easy for audience to follow along with transitions
section_header() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
}

# ============================================================================
# DEMO INTRODUCTION
# ============================================================================
# The opening sets expectations and establishes the narrative framework.
# Using box-drawing characters creates a professional-looking header.
# ============================================================================
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  AKS Regulated Enterprise Security Demo  ║${NC}"
echo -e "${BOLD}║  Attack → Detect → Prevent → Prove       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "This interactive script walks through a 20-minute security demo."
echo "Each section pauses so you can talk through what's happening."
pause

# ============================================================================
# SETUP: DEPLOY VULNERABLE WORKLOAD
# ============================================================================
# The vulnerable app is INTENTIONALLY insecure to demonstrate:
#   - Running as root
#   - Missing resource limits
#   - Overly permissive RBAC (can read secrets across namespaces)
#   - No security context
#   - No network policies
#
# This represents a common "lift and shift" deployment where security
# wasn't considered. Many organizations have workloads like this.
#
# WHY AN INTENTIONALLY VULNERABLE APP?
#   We need to show attacks actually working. A properly secured app
#   would make the attack simulations fail, defeating the demo purpose.
#   The "before Kyverno" state needs to be demonstrably insecure.
# ============================================================================
section_header "SETUP: Deploy Vulnerable Workload"

echo -e "${YELLOW}Deploying the intentionally insecure application...${NC}"

# Create namespace first (ignore if exists)
kubectl apply -f "${ROOT_DIR}/workloads/vulnerable-app/namespace.yaml" 2>/dev/null || true

# Deploy all resources in the vulnerable-app directory
kubectl apply -f "${ROOT_DIR}/workloads/vulnerable-app/"
echo ""
echo -e "${GREEN}Vulnerable app deployed. Waiting for pod to be ready...${NC}"

# Wait for pod readiness with timeout
# The 'or echo' prevents the script from failing if wait times out
kubectl wait --for=condition=ready pod -l app=vulnerable-app \
    -n vulnerable-app --timeout=60s 2>/dev/null || echo "  (Pod may take a moment)"
pause

# ============================================================================
# PART 1: ATTACK - KUBEHOUND ANALYSIS
# ============================================================================
# KubeHound is an ATTACK PATH ANALYZER that thinks like an attacker.
# It builds a graph of your cluster and finds paths from:
#   - Compromised pods → Secrets access
#   - Compromised pods → Other nodes
#   - Compromised pods → Cluster admin
#
# HOW KUBEHOUND WORKS:
#   1. Collects data from Kubernetes API (pods, roles, bindings, etc.)
#   2. Builds a graph database (Neo4j)
#   3. Runs graph queries to find attack paths
#   4. Visualizes paths in an interactive UI
#
# WHY ATTACK PATH ANALYSIS?
#   Traditional tools find vulnerabilities in isolation. KubeHound shows
#   how vulnerabilities CHAIN TOGETHER. A "medium" vulnerability in a pod
#   combined with overly permissive RBAC becomes a critical path to
#   cluster admin.
#
# KEY DEMO POINTS:
#   - Show the attack graph visualization
#   - Highlight the path from vulnerable-app to secrets
#   - Discuss how RBAC configuration enabled the attack
# ============================================================================
section_header "PART 1: ATTACK - KubeHound Attack Path Analysis (5 min)"

echo "KubeHound shows how an attacker sees your cluster."
echo "It maps paths from compromised pods to cluster-admin."
echo ""
echo -e "${YELLOW}Key talking points:${NC}"
echo "  - The vulnerable app has a ClusterRole with secrets access"
echo "  - An attacker in this pod can read secrets across namespaces"
echo "  - KubeHound visualizes these attack paths in a graph database"
echo ""
echo -e "${YELLOW}To run KubeHound (if docker is available):${NC}"
echo "  cd ${ROOT_DIR}/tools/kubehound"
echo "  docker compose up -d"
echo "  docker compose exec kubehound kubehound"
echo ""
echo "See: tools/kubehound/queries/ for pre-built queries"
pause

# ============================================================================
# PART 2: DETECT - FALCO RUNTIME DETECTION
# ============================================================================
# This is the CORE of the demo - showing Falco catching attacks in
# real-time. We run three attack simulation scripts that trigger
# various Falco rules.
#
# ATTACK SIMULATIONS:
#   01-reconnaissance.sh - Environment discovery, token reading
#   02-credential-theft.sh - API access, secret enumeration
#   03-lateral-movement.sh - Privilege escalation, service discovery
#
# DEMO TIP: Have Falco logs open in a separate terminal:
#   kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=1m
#
# Each attack triggers specific Falco rules that map to MITRE ATT&CK
# techniques. This shows the audience that detection is immediate
# and actionable.
#
# KEY MESSAGES:
#   - Attacks are detected in SECONDS, not days
#   - Alerts include context (pod, user, command)
#   - MITRE ATT&CK mapping aids investigation
#   - Integration with SIEM enables correlation
# ============================================================================
section_header "PART 2: DETECT - Falco Runtime Detection (7 min)"

echo -e "${YELLOW}Starting Falco log monitoring in background...${NC}"
echo "  (Open a separate terminal to see real-time alerts)"
echo "  kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=1m"
echo ""
pause

# Run reconnaissance simulation
echo -e "${YELLOW}Running reconnaissance simulation...${NC}"
"${ROOT_DIR}/scenarios/attack-detect-prevent/01-reconnaissance.sh"
pause

# Run credential theft simulation
echo -e "${YELLOW}Running credential theft simulation...${NC}"
"${ROOT_DIR}/scenarios/attack-detect-prevent/02-credential-theft.sh"
pause

# Run lateral movement simulation
echo -e "${YELLOW}Running lateral movement simulation...${NC}"
"${ROOT_DIR}/scenarios/attack-detect-prevent/03-lateral-movement.sh"
pause

echo -e "${YELLOW}Key talking points:${NC}"
echo "  - Falco detected service account token reads"
echo "  - Kubernetes API secrets access triggered CRITICAL alerts"
echo "  - All alerts include MITRE ATT&CK technique IDs"
echo "  - Alerts flow through Falcosidekick to SIEM/Slack/Teams"
pause

# ============================================================================
# PART 3: PREVENT - KYVERNO POLICY ENFORCEMENT
# ============================================================================
# Now we show how to PREVENT these issues from happening in the first
# place. Kyverno policies act as admission control - blocking bad
# deployments before they run.
#
# THE SHIFT-LEFT NARRATIVE:
#   - Detection is important, but prevention is better
#   - Catch issues at deploy time, not in production
#   - Developers get immediate feedback on violations
#   - Compliance is enforced automatically
#
# DEMO FLOW:
#   1. Apply Kyverno policies
#   2. Delete the vulnerable app
#   3. Try to recreate it - Kyverno REJECTS it
#   4. Deploy the compliant version - Kyverno ALLOWS it
#
# KEY POLICIES:
#   - require-non-root: Containers must run as non-root
#   - require-readonly-root: Root filesystem must be read-only
#   - require-resource-limits: CPU/memory limits required
#   - restrict-privilege-escalation: No allowPrivilegeEscalation
#   - require-security-context: securityContext must be defined
#   - restrict-host-namespaces: No hostNetwork, hostPID, hostIPC
#
# COMPLIANCE MAPPING:
#   Each policy maps to specific regulatory requirements from
#   NCUA, OSFI, DORA, SOC2, etc.
# ============================================================================
section_header "PART 3: PREVENT - Kyverno Policy Enforcement (8 min)"

echo -e "${YELLOW}Applying Kyverno policies...${NC}"
kubectl apply -k "${ROOT_DIR}/tools/kyverno/policies/"
echo ""
echo -e "${GREEN}6 policies applied (4 Enforce, 2 Audit)${NC}"
echo ""

# Show installed policies
kubectl get clusterpolicies
pause

# Demonstrate policy enforcement
echo -e "${YELLOW}Attempting to redeploy vulnerable app (should be REJECTED)...${NC}"
echo ""

# First delete the existing deployment
kubectl delete deployment vulnerable-app -n vulnerable-app 2>/dev/null || true
sleep 2

# Try to recreate - this should fail due to Kyverno policies
if kubectl apply -f "${ROOT_DIR}/workloads/vulnerable-app/deployment.yaml" 2>&1; then
    echo -e "${RED}  Unexpected: deployment was accepted${NC}"
else
    echo ""
    echo -e "${GREEN}  Deployment REJECTED by Kyverno!${NC}"
fi
pause

# Now show the compliant app works
echo -e "${YELLOW}Deploying compliant application (should SUCCEED)...${NC}"
kubectl apply -f "${ROOT_DIR}/workloads/compliant-app/namespace.yaml" 2>/dev/null || true
kubectl apply -f "${ROOT_DIR}/workloads/compliant-app/"
echo ""
echo -e "${GREEN}  Compliant app deployed successfully!${NC}"
echo ""
echo -e "${YELLOW}Key talking points:${NC}"
echo "  - Each policy maps to regulatory requirements (NCUA, OSFI, DORA)"
echo "  - Enforce mode blocks non-compliant deployments at admission"
echo "  - Audit mode creates reports without blocking"
echo "  - Shift-left: catch issues before they reach production"
pause

# ============================================================================
# FINALE: PROVE - COMPLIANCE POSTURE
# ============================================================================
# The final act shows measurable improvement. Kubescape scans before
# and after policies show a quantifiable compliance delta.
#
# THE AUDITOR'S PERSPECTIVE:
#   Regulated industries need EVIDENCE. Kubescape provides:
#   - Numerical compliance scores
#   - Per-control pass/fail status
#   - Historical tracking
#   - Export to JSON/HTML for auditors
#
# FRAMEWORK MAPPING:
#   - NSA Kubernetes Hardening Guide
#   - CIS Benchmarks
#   - SOC2 controls
#   - MITRE ATT&CK
#
# THE COMPLIANCE DELTA:
#   Before Kyverno: ~67% (vulnerable workloads allowed)
#   After Kyverno:  ~94% (only compliant workloads allowed)
#
# This quantifiable improvement is compelling for executives and
# auditors who need metrics to report.
# ============================================================================
section_header "FINALE: PROVE - Compliance Posture (Kubescape)"

echo -e "${YELLOW}Running Kubescape compliance scan...${NC}"
echo ""

# Check if kubescape CLI is installed locally
if command -v kubescape >/dev/null 2>&1; then
    echo "  Scanning with NSA framework..."
    kubescape scan framework nsa --include-namespaces compliant-app 2>&1 | tail -20
else
    echo "  (kubescape CLI not installed locally)"
    echo "  Run in-cluster: kubectl exec -n kubescape deploy/kubescape -- kubescape scan framework nsa"
fi
echo ""
echo -e "${YELLOW}Key talking points:${NC}"
echo "  - Before Kyverno: ~67% compliance score"
echo "  - After Kyverno: ~94% compliance score"
echo "  - Kubescape maps to NSA, SOC2, MITRE frameworks"
echo "  - Reports serve as compliance evidence for auditors"
echo "  - Trivy provides SBOM for supply chain transparency"
pause

# ============================================================================
# DEMO SUMMARY
# ============================================================================
# End with a clear summary that reinforces the key messages.
# The four-part framework (Attack/Detect/Prevent/Prove) should
# be memorable and actionable.
# ============================================================================
section_header "DEMO COMPLETE"

echo -e "${GREEN}Security Stack Summary:${NC}"
echo ""
echo "  1. ATTACK  - KubeHound showed attack paths from pods to cluster-admin"
echo "  2. DETECT  - Falco caught runtime attacks with MITRE ATT&CK mapping"
echo "  3. PREVENT - Kyverno blocked non-compliant deployments at admission"
echo "  4. PROVE   - Kubescape demonstrated compliance improvement"
echo ""
echo -e "${BOLD}All tools are CNCF projects, open source, and production-ready.${NC}"
echo ""
echo "Cleanup: ./cleanup.sh"
