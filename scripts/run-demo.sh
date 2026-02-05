#!/usr/bin/env bash
# Interactive demo walkthrough script
# Guides through the Attack -> Detect -> Prevent -> Prove narrative

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

pause() {
    echo ""
    echo -e "${BLUE}  Press Enter to continue...${NC}"
    read -r
}

section_header() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
}

echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  AKS Regulated Enterprise Security Demo  ║${NC}"
echo -e "${BOLD}║  Attack → Detect → Prevent → Prove       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "This interactive script walks through a 20-minute security demo."
echo "Each section pauses so you can talk through what's happening."
pause

# ============================================
# SETUP: Deploy vulnerable workload
# ============================================
section_header "SETUP: Deploy Vulnerable Workload"

echo -e "${YELLOW}Deploying the intentionally insecure application...${NC}"
kubectl apply -f "${ROOT_DIR}/demo-workloads/vulnerable-app/namespace.yaml" 2>/dev/null || true
kubectl apply -f "${ROOT_DIR}/demo-workloads/vulnerable-app/"
echo ""
echo -e "${GREEN}Vulnerable app deployed. Waiting for pod to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=vulnerable-app \
    -n vulnerable-app --timeout=60s 2>/dev/null || echo "  (Pod may take a moment)"
pause

# ============================================
# PART 1: ATTACK (5 minutes)
# ============================================
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
echo "  cd ${ROOT_DIR}/security-tools/kubehound"
echo "  docker compose up -d"
echo "  docker compose exec kubehound kubehound"
echo ""
echo "See: security-tools/kubehound/queries/ for pre-built queries"
pause

# ============================================
# PART 2: DETECT (7 minutes)
# ============================================
section_header "PART 2: DETECT - Falco Runtime Detection (7 min)"

echo -e "${YELLOW}Starting Falco log monitoring in background...${NC}"
echo "  (Open a separate terminal to see real-time alerts)"
echo "  kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=1m"
echo ""
pause

echo -e "${YELLOW}Running reconnaissance simulation...${NC}"
"${ROOT_DIR}/attack-simulation/01-reconnaissance.sh"
pause

echo -e "${YELLOW}Running credential theft simulation...${NC}"
"${ROOT_DIR}/attack-simulation/02-credential-theft.sh"
pause

echo -e "${YELLOW}Running lateral movement simulation...${NC}"
"${ROOT_DIR}/attack-simulation/03-lateral-movement.sh"
pause

echo -e "${YELLOW}Key talking points:${NC}"
echo "  - Falco detected service account token reads"
echo "  - Kubernetes API secrets access triggered CRITICAL alerts"
echo "  - All alerts include MITRE ATT&CK technique IDs"
echo "  - Alerts flow through Falcosidekick to SIEM/Slack/Teams"
pause

# ============================================
# PART 3: PREVENT (8 minutes)
# ============================================
section_header "PART 3: PREVENT - Kyverno Policy Enforcement (8 min)"

echo -e "${YELLOW}Applying Kyverno policies...${NC}"
kubectl apply -k "${ROOT_DIR}/security-tools/kyverno/policies/"
echo ""
echo -e "${GREEN}6 policies applied (4 Enforce, 2 Audit)${NC}"
echo ""
kubectl get clusterpolicies
pause

echo -e "${YELLOW}Attempting to redeploy vulnerable app (should be REJECTED)...${NC}"
echo ""
kubectl delete deployment vulnerable-app -n vulnerable-app 2>/dev/null || true
sleep 2
if kubectl apply -f "${ROOT_DIR}/demo-workloads/vulnerable-app/deployment.yaml" 2>&1; then
    echo -e "${RED}  Unexpected: deployment was accepted${NC}"
else
    echo ""
    echo -e "${GREEN}  Deployment REJECTED by Kyverno!${NC}"
fi
pause

echo -e "${YELLOW}Deploying compliant application (should SUCCEED)...${NC}"
kubectl apply -f "${ROOT_DIR}/demo-workloads/compliant-app/namespace.yaml" 2>/dev/null || true
kubectl apply -f "${ROOT_DIR}/demo-workloads/compliant-app/"
echo ""
echo -e "${GREEN}  Compliant app deployed successfully!${NC}"
echo ""
echo -e "${YELLOW}Key talking points:${NC}"
echo "  - Each policy maps to regulatory requirements (NCUA, OSFI, DORA)"
echo "  - Enforce mode blocks non-compliant deployments at admission"
echo "  - Audit mode creates reports without blocking"
echo "  - Shift-left: catch issues before they reach production"
pause

# ============================================
# FINALE: PROVE
# ============================================
section_header "FINALE: PROVE - Compliance Posture (Kubescape)"

echo -e "${YELLOW}Running Kubescape compliance scan...${NC}"
echo ""
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

# ============================================
# SUMMARY
# ============================================
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
