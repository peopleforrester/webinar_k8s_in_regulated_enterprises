#!/usr/bin/env bash
# ============================================================================
# ABOUTME: Generates comprehensive compliance reports using Kubescape and Trivy.
# ABOUTME: Produces audit-ready JSON reports for NSA, SOC2, MITRE, and vulnerability scans.
# ============================================================================
#
# PURPOSE:
#   This script generates compliance reports that serve as EVIDENCE for
#   auditors and regulatory examinations. In regulated industries, you
#   must prove compliance, not just claim it. These reports provide:
#
#   1. NSA Kubernetes Hardening Report
#      - Based on NSA/CISA Kubernetes Hardening Guide
#      - 47 controls covering pod security, network, RBAC, etc.
#      - Widely recognized by government and financial regulators
#
#   2. SOC2 Compliance Report
#      - Maps to SOC2 Trust Service Criteria
#      - Covers security, availability, processing integrity
#      - Required for many B2B relationships
#
#   3. MITRE ATT&CK Report
#      - Maps controls to MITRE ATT&CK framework
#      - Shows defense coverage against known attack techniques
#      - Useful for security teams and red/blue exercises
#
#   4. Vulnerability Report (Trivy)
#      - Scans all images in cluster for CVEs
#      - Provides severity ratings and fix versions
#      - Essential for vulnerability management programs
#
#   5. Kyverno Policy Reports
#      - Shows policy violations by namespace
#      - Tracks compliance over time
#      - Useful for policy tuning and exceptions
#
# REGULATORY CONTEXT:
#   These reports help satisfy requirements from:
#   - NCUA: Supervisory examinations for credit unions
#   - OSFI: B-10/B-13 technology risk guidelines (Canada)
#   - DORA: Digital Operational Resilience Act (EU)
#   - SOC2: Service Organization Control reports
#   - PCI-DSS: Payment Card Industry requirements
#
# PREREQUISITES:
#   - kubescape CLI (recommended) or kubescape in-cluster
#   - trivy CLI (recommended) for vulnerability scanning
#   - kubectl access to the cluster
#
# USAGE:
#   ./generate-compliance-report.sh
#
# OUTPUT:
#   Reports are saved to ../reports/ with timestamps:
#   - nsa_YYYYMMDD_HHMMSS.json
#   - soc2_YYYYMMDD_HHMMSS.json
#   - mitre_YYYYMMDD_HHMMSS.json
#   - vulnerabilities_YYYYMMDD_HHMMSS.json
#   - kyverno_policy_reports_YYYYMMDD_HHMMSS.json
#   - kyverno_cluster_reports_YYYYMMDD_HHMMSS.json
#
# ESTIMATED TIME: 5-10 minutes depending on cluster size
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${SCRIPT_DIR}/../reports"

# Terminal colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Timestamp for unique report filenames
# Format: YYYYMMDD_HHMMSS for chronological sorting
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ----------------------------------------------------------------------------
# PROGRESS TRACKING
# ----------------------------------------------------------------------------
# Compliance scans take several minutes. Progress indicators help users
# understand how far along the process is and estimate remaining time.
# ----------------------------------------------------------------------------
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

# Create reports directory if it doesn't exist
# The -p flag prevents errors if directory already exists
mkdir -p "${REPORT_DIR}"

# ============================================================================
# TOOL AVAILABILITY CHECK
# ============================================================================
# We check for CLI tools before starting. The script can still generate
# some reports even if not all tools are installed, so we track availability
# per-tool rather than failing immediately.
#
# INSTALLATION COMMANDS:
#   kubescape: curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash
#   trivy: curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh
# ============================================================================
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

# ============================================================================
# NSA KUBERNETES HARDENING FRAMEWORK SCAN
# ============================================================================
# The NSA/CISA Kubernetes Hardening Guide is a comprehensive security
# baseline developed by US government cybersecurity agencies.
#
# WHAT IT CHECKS:
#   - Pod Security Standards (restricted vs privileged)
#   - Network policies and segmentation
#   - RBAC configuration and least privilege
#   - Secret management practices
#   - Logging and auditing configuration
#   - Image scanning and provenance
#
# WHY NSA FRAMEWORK:
#   - Developed by credible security organizations
#   - Widely recognized across industries
#   - Maps well to other frameworks (CIS, SOC2)
#   - Updated regularly with new guidance
#
# OUTPUT FORMAT:
#   JSON output includes:
#   - Overall compliance score (percentage)
#   - Per-control pass/fail status
#   - Specific resources that failed
#   - Remediation guidance for failures
# ============================================================================
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

# ============================================================================
# SOC2 COMPLIANCE SCAN
# ============================================================================
# SOC2 (Service Organization Control 2) is an auditing framework
# that evaluates an organization's controls related to:
#   - Security: Protection against unauthorized access
#   - Availability: System uptime and accessibility
#   - Processing Integrity: Accurate data processing
#   - Confidentiality: Data protection
#   - Privacy: Personal information handling
#
# WHY SOC2:
#   - Required by many enterprise customers
#   - Standard for SaaS and cloud providers
#   - Demonstrates mature security practices
#   - Often required in vendor assessments
#
# KUBESCAPE SOC2 MAPPING:
#   Kubescape maps Kubernetes controls to SOC2 Trust Service Criteria.
#   This provides evidence for the "Security" and "Availability" criteria.
# ============================================================================
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

# ============================================================================
# MITRE ATT&CK FRAMEWORK SCAN
# ============================================================================
# MITRE ATT&CK is a knowledge base of adversary tactics and techniques.
# It provides a common language for describing attacks and defenses.
#
# WHAT IT COVERS:
#   - Initial Access: How attackers get in
#   - Execution: How attackers run code
#   - Persistence: How attackers maintain access
#   - Privilege Escalation: How attackers gain higher privileges
#   - Defense Evasion: How attackers avoid detection
#   - Credential Access: How attackers steal credentials
#   - Discovery: How attackers learn about the environment
#   - Lateral Movement: How attackers spread
#   - Collection: How attackers gather data
#   - Exfiltration: How attackers steal data
#   - Impact: How attackers cause damage
#
# WHY MITRE:
#   - Universal framework understood by security teams
#   - Maps Falco alerts to specific techniques
#   - Helps prioritize security investments
#   - Useful for threat modeling and red team exercises
# ============================================================================
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

# ============================================================================
# VULNERABILITY SCAN
# ============================================================================
# Trivy scans all container images in the cluster for:
#   - Known vulnerabilities (CVEs) in packages
#   - Misconfigurations in Dockerfiles
#   - Exposed secrets in images
#   - License compliance issues
#
# WHY CONTINUOUS VULNERABILITY SCANNING:
#   - New CVEs are published daily
#   - Images that were "clean" may become vulnerable
#   - Regulators expect vulnerability management
#   - Supply chain attacks target dependencies
#
# REPORT CONTENTS:
#   - List of all images in cluster
#   - CVEs found with severity (CRITICAL, HIGH, MEDIUM, LOW)
#   - Fixed versions where available
#   - CVSS scores for prioritization
#
# REGULATORY RELEVANCE:
#   - DORA requires vulnerability management
#   - SOC2 requires vulnerability assessment
#   - PCI-DSS requires regular scanning
#   - NCUA expects risk management
# ============================================================================
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

# ============================================================================
# KYVERNO POLICY REPORTS
# ============================================================================
# Kyverno generates Policy Reports as Kubernetes resources. These show:
#   - Which resources passed/failed each policy
#   - When violations occurred
#   - What the violation message was
#
# REPORT TYPES:
#   - PolicyReport (polr): Namespace-scoped violations
#   - ClusterPolicyReport (cpolr): Cluster-scoped violations
#
# WHY POLICY REPORTS:
#   - Track compliance over time
#   - Identify repeat offenders
#   - Tune policies based on real violations
#   - Provide evidence for auditors
#
# These reports complement Kubescape by showing DYNAMIC policy violations
# (what was blocked at admission) vs STATIC configuration analysis
# (what Kubescape finds in existing resources).
# ============================================================================
progress "Collecting Kyverno policy reports..."

# Get namespace-scoped policy reports
kubectl get polr -A -o json > "${REPORT_DIR}/kyverno_policy_reports_${TIMESTAMP}.json" 2>/dev/null || \
    echo -e "${YELLOW}  No Kyverno policy reports found${NC}"

# Get cluster-scoped policy reports
kubectl get cpolr -o json > "${REPORT_DIR}/kyverno_cluster_reports_${TIMESTAMP}.json" 2>/dev/null || \
    echo -e "${YELLOW}  No Kyverno cluster reports found${NC}"

echo -e "${GREEN}  Kyverno reports collected${NC}"
echo ""

# ============================================================================
# SUMMARY
# ============================================================================
# Final summary shows where reports were saved and how to use them.
# The regulatory context helps users understand the value of these
# reports beyond just technical compliance.
# ============================================================================
echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}  Compliance reports generated (100%)${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "Reports saved to: ${REPORT_DIR}/"
echo ""

# List generated reports with details
ls -la "${REPORT_DIR}/"*"${TIMESTAMP}"* 2>/dev/null || echo "  (No reports generated)"
echo ""

# Explain regulatory applicability
echo "These reports can be used as compliance evidence for:"
echo "  - NCUA supervisory examinations"
echo "  - OSFI B-10/B-13 compliance"
echo "  - DORA operational resilience reviews"
echo "  - SOC2 audit evidence"
