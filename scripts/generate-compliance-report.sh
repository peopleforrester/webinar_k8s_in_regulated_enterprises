#!/usr/bin/env bash
# Generate compliance report using Kubescape and Trivy
# Produces reports for NSA, SOC2, and MITRE frameworks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${SCRIPT_DIR}/../reports"
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TOTAL_STEPS=5
CURRENT_STEP=0

progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local PCT=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo -e "${YELLOW}[${CURRENT_STEP}/${TOTAL_STEPS}] (${PCT}%) $1${NC}"
}

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Compliance Report Generation${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# Create reports directory
mkdir -p "${REPORT_DIR}"

# Check tool availability
HAS_KUBESCAPE=false
HAS_TRIVY=false
command -v kubescape >/dev/null 2>&1 && HAS_KUBESCAPE=true
command -v trivy >/dev/null 2>&1 && HAS_TRIVY=true

if [[ "${HAS_KUBESCAPE}" == "false" ]] && [[ "${HAS_TRIVY}" == "false" ]]; then
    echo -e "${RED}Neither kubescape nor trivy CLI found.${NC}"
    echo "Install: curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash"
    echo "Install: curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh"
    exit 1
fi

# NSA Framework Scan
progress "Running NSA Hardening Framework scan..."
if [[ "${HAS_KUBESCAPE}" == "true" ]]; then
    kubescape scan framework nsa \
        --format json \
        --output "${REPORT_DIR}/nsa_${TIMESTAMP}.json" \
        2>&1 | tail -5
    echo -e "${GREEN}  NSA report: ${REPORT_DIR}/nsa_${TIMESTAMP}.json${NC}"
else
    echo -e "${YELLOW}  Skipped (kubescape not installed)${NC}"
fi
echo ""

# SOC2 Framework Scan
progress "Running SOC2 compliance scan..."
if [[ "${HAS_KUBESCAPE}" == "true" ]]; then
    kubescape scan framework soc2 \
        --format json \
        --output "${REPORT_DIR}/soc2_${TIMESTAMP}.json" \
        2>&1 | tail -5
    echo -e "${GREEN}  SOC2 report: ${REPORT_DIR}/soc2_${TIMESTAMP}.json${NC}"
else
    echo -e "${YELLOW}  Skipped (kubescape not installed)${NC}"
fi
echo ""

# MITRE ATT&CK Scan
progress "Running MITRE ATT&CK framework scan..."
if [[ "${HAS_KUBESCAPE}" == "true" ]]; then
    kubescape scan framework mitre \
        --format json \
        --output "${REPORT_DIR}/mitre_${TIMESTAMP}.json" \
        2>&1 | tail -5
    echo -e "${GREEN}  MITRE report: ${REPORT_DIR}/mitre_${TIMESTAMP}.json${NC}"
else
    echo -e "${YELLOW}  Skipped (kubescape not installed)${NC}"
fi
echo ""

# Vulnerability Scan
progress "Running vulnerability scan..."
if [[ "${HAS_TRIVY}" == "true" ]]; then
    trivy k8s --report summary \
        --format json \
        --output "${REPORT_DIR}/vulnerabilities_${TIMESTAMP}.json" \
        2>&1 | tail -5
    echo -e "${GREEN}  Vulnerability report: ${REPORT_DIR}/vulnerabilities_${TIMESTAMP}.json${NC}"
else
    echo -e "${YELLOW}  Skipped (trivy not installed)${NC}"
fi
echo ""

# Kyverno Policy Reports
progress "Collecting Kyverno policy reports..."
kubectl get polr -A -o json > "${REPORT_DIR}/kyverno_policy_reports_${TIMESTAMP}.json" 2>/dev/null || \
    echo -e "${YELLOW}  No Kyverno policy reports found${NC}"
kubectl get cpolr -o json > "${REPORT_DIR}/kyverno_cluster_reports_${TIMESTAMP}.json" 2>/dev/null || \
    echo -e "${YELLOW}  No Kyverno cluster reports found${NC}"
echo -e "${GREEN}  Kyverno reports collected${NC}"
echo ""

echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}  Compliance reports generated (100%)${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "Reports saved to: ${REPORT_DIR}/"
echo ""
ls -la "${REPORT_DIR}/"*"${TIMESTAMP}"* 2>/dev/null || echo "  (No reports generated)"
echo ""
echo "These reports can be used as compliance evidence for:"
echo "  - NCUA supervisory examinations"
echo "  - OSFI B-10/B-13 compliance"
echo "  - DORA operational resilience reviews"
echo "  - SOC2 audit evidence"
