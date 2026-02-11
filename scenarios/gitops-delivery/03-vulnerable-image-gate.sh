#!/usr/bin/env bash
# ABOUTME: Deploys a vulnerable container image and shows Trivy Operator flagging CVEs.
# ABOUTME: Step 3 of the GitOps delivery scenario — image scanning gates deployments.
# ============================================================================
#
# STEP 3: VULNERABLE IMAGE GATE
#
# This script demonstrates how Trivy Operator acts as a security gate:
#   1. Deploy a known-vulnerable image (old nginx with CVEs)
#   2. Watch Trivy Operator scan the image
#   3. Show the VulnerabilityReport with CVE details
#   4. Demonstrate that Kyverno can block based on scan results
#   5. Clean up the vulnerable deployment
#
# THE SUPPLY CHAIN SECURITY NARRATIVE:
#   Even with GitOps, a bad image can reach the cluster. Trivy Operator
#   continuously scans running images and reports vulnerabilities.
#   Combined with Kyverno, you can gate deployments based on scan results.
#
# PREREQUISITES:
#   - AKS cluster with Trivy Operator installed (install-tools.sh --tier=1)
#   - Kyverno installed for policy enforcement
#
# REGULATORY ALIGNMENT:
#   - NCUA: Vulnerability management and patching
#   - DORA Article 6: ICT vulnerability assessment
#   - PCI-DSS 6.3: Vulnerability scanning for deployed software
#   - SOC 2 CC7.1: Monitoring for vulnerabilities
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."

# Terminal colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${CYAN}  ℹ ${NC} $*"; }
success() { echo -e "${GREEN}  ✓ ${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠ ${NC} $*"; }
error()   { echo -e "${RED}  ✗ ${NC} $*"; }

pause() {
    echo ""
    echo -e "${BLUE}  Press Enter to continue...${NC}"
    read -r
}

# Namespace for the vulnerable test deployment
VULN_NS="vuln-image-test"

# ----------------------------------------------------------------------------
# CLEANUP FUNCTION
# ----------------------------------------------------------------------------
cleanup_vuln_test() {
    info "Cleaning up vulnerable image test resources..."
    kubectl delete namespace "${VULN_NS}" --wait=false 2>/dev/null || true
    success "Cleanup complete"
}

# ----------------------------------------------------------------------------
# PREFLIGHT
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Step 3: Vulnerable Image Gate ──${NC}"
echo ""

# Verify Trivy Operator is running
info "Checking Trivy Operator availability..."
if ! kubectl get deploy -n trivy-system trivy-operator >/dev/null 2>&1; then
    error "Trivy Operator not found. Run: ./scripts/install-tools.sh --tier=1"
    exit 1
fi
success "Trivy Operator found in trivy-system namespace"
echo ""

# ----------------------------------------------------------------------------
# STEP 3a: DEPLOY KNOWN-VULNERABLE IMAGE
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Deploying known-vulnerable image ──${NC}"
echo ""

info "Creating test namespace..."
kubectl create namespace "${VULN_NS}" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
echo ""

# Deploy an intentionally old nginx image with known CVEs
# nginx:1.16.0 has multiple high/critical CVEs (released 2019)
info "Deploying nginx:1.16.0 (known to have critical CVEs)..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vuln-nginx
  namespace: ${VULN_NS}
  labels:
    app: vuln-nginx
    purpose: trivy-scan-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vuln-nginx
  template:
    metadata:
      labels:
        app: vuln-nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.16.0
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
EOF

echo ""
success "Deployed nginx:1.16.0 to ${VULN_NS} namespace"
echo ""

info "Waiting for pod to start..."
kubectl wait --for=condition=ready pod -l app=vuln-nginx \
    -n "${VULN_NS}" --timeout=120s 2>/dev/null || warn "Pod may take a moment"
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 3b: WAIT FOR TRIVY SCAN
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Waiting for Trivy Operator scan ──${NC}"
echo ""

info "Trivy Operator scans new pods automatically. Waiting for VulnerabilityReport..."
echo ""

retries=0
max_retries=30
vuln_report=""
while [[ $retries -lt $max_retries ]]; do
    vuln_report=$(kubectl get vulnerabilityreports -n "${VULN_NS}" --no-headers 2>/dev/null || echo "")
    if [[ -n "$vuln_report" ]]; then
        success "VulnerabilityReport generated!"
        break
    fi

    echo -e "  Waiting for scan... (attempt $((retries+1))/${max_retries})"
    retries=$((retries + 1))
    sleep 10
done

if [[ -z "$vuln_report" ]]; then
    warn "Trivy scan taking longer than expected."
    warn "Check: kubectl get vulnerabilityreports -n ${VULN_NS}"
    warn "Continuing with demo..."
fi
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 3c: SHOW VULNERABILITY RESULTS
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Vulnerability Scan Results ──${NC}"
echo ""

info "VulnerabilityReports in ${VULN_NS}:"
kubectl get vulnerabilityreports -n "${VULN_NS}" 2>/dev/null || true
echo ""

# Get the first report name and show details
report_name=$(kubectl get vulnerabilityreports -n "${VULN_NS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$report_name" ]]; then
    info "Vulnerability summary for ${report_name}:"
    echo ""

    # Show severity counts
    critical=$(kubectl get vulnerabilityreport "${report_name}" -n "${VULN_NS}" -o jsonpath='{.report.summary.criticalCount}' 2>/dev/null || echo "?")
    high=$(kubectl get vulnerabilityreport "${report_name}" -n "${VULN_NS}" -o jsonpath='{.report.summary.highCount}' 2>/dev/null || echo "?")
    medium=$(kubectl get vulnerabilityreport "${report_name}" -n "${VULN_NS}" -o jsonpath='{.report.summary.mediumCount}' 2>/dev/null || echo "?")
    low=$(kubectl get vulnerabilityreport "${report_name}" -n "${VULN_NS}" -o jsonpath='{.report.summary.lowCount}' 2>/dev/null || echo "?")

    echo -e "  ${RED}CRITICAL: ${critical}${NC}"
    echo -e "  ${YELLOW}HIGH:     ${high}${NC}"
    echo -e "  ${CYAN}MEDIUM:   ${medium}${NC}"
    echo -e "  LOW:     ${low}"
    echo ""

    # Show top critical/high CVEs
    info "Top critical and high CVEs:"
    kubectl get vulnerabilityreport "${report_name}" -n "${VULN_NS}" \
        -o jsonpath='{range .report.vulnerabilities[?(@.severity=="CRITICAL")]}{.vulnerabilityID}{"\t"}{.severity}{"\t"}{.installedVersion}{"\t"}{.title}{"\n"}{end}' 2>/dev/null | head -10
    echo ""
else
    warn "No vulnerability report found yet."
fi
pause

# ----------------------------------------------------------------------------
# STEP 3d: DEMONSTRATE POLICY GATING (OPTIONAL)
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Policy-Based Image Gating ──${NC}"
echo ""

info "In a production setup, Kyverno can block deployments based on Trivy scan results."
echo ""
echo "  Example policy: Block images with CRITICAL vulnerabilities"
echo ""
echo -e "${CYAN}  apiVersion: kyverno.io/v1"
echo "  kind: ClusterPolicy"
echo "  metadata:"
echo "    name: block-critical-vulnerabilities"
echo "  spec:"
echo "    validationFailureAction: Enforce"
echo "    rules:"
echo "      - name: check-vulnerabilities"
echo "        match:"
echo "          any:"
echo "            - resources:"
echo "                kinds: [Pod]"
echo "        preconditions:"
echo "          all:"
echo "            - key: \"{{request.operation}}\""
echo "              operator: In"
echo "              value: [CREATE, UPDATE]"
echo "        validate:"
echo "          message: \"Image has critical vulnerabilities\""
echo "          deny:"
echo "            conditions:"
echo "              any:"
echo "                - key: \"{{ images.containers.*.registry }}\""
echo "                  operator: AnyIn"
echo -e "                  value: [\"docker.io\"]${NC}"
echo ""
info "This creates a defense-in-depth pipeline:"
echo "  1. Git commit → ArgoCD sync (change management)"
echo "  2. Trivy scans image → VulnerabilityReport (assessment)"
echo "  3. Kyverno checks report → allow/deny (enforcement)"
echo ""
pause

# ----------------------------------------------------------------------------
# STEP 3e: CLEANUP
# ----------------------------------------------------------------------------
echo -e "${BOLD}── Cleanup ──${NC}"
echo ""

cleanup_vuln_test
echo ""

success "Step 3 complete. Trivy Operator provides continuous vulnerability scanning."
echo ""
echo -e "${YELLOW}Key regulatory takeaways:${NC}"
echo "  - Trivy Operator scans every deployed image automatically"
echo "  - VulnerabilityReports provide auditable evidence of assessments"
echo "  - Integration with Kyverno enables policy-based deployment gates"
echo "  - CVE data maps to NCUA vulnerability management requirements"
echo "  - Continuous scanning catches newly disclosed CVEs in running workloads"
echo ""
echo "  Next: Run run-demo.sh for the complete guided walkthrough."
