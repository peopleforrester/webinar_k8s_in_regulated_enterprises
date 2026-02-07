#!/usr/bin/env bash
# ============================================================================
# ABOUTME: Installs the complete security tool stack via Helm charts.
# ABOUTME: Deploys Falco, Falcosidekick, Kyverno, Trivy Operator, and Kubescape.
# ============================================================================
#
# PURPOSE:
#   This script deploys a comprehensive cloud-native security stack that
#   addresses multiple aspects of Kubernetes security:
#
#   1. FALCO (Runtime Threat Detection)
#      - Monitors system calls using eBPF or kernel module
#      - Detects container escapes, privilege escalation, credential theft
#      - Uses rules based on MITRE ATT&CK framework
#      - Project: https://falco.org / CNCF Graduated
#
#   2. FALCOSIDEKICK (Alert Routing)
#      - Forwards Falco alerts to 50+ destinations
#      - Supports SIEM, Slack, Teams, PagerDuty, Prometheus, etc.
#      - Provides alert enrichment and filtering
#      - Project: https://github.com/falcosecurity/falcosidekick
#
#   3. KYVERNO (Policy Engine)
#      - Kubernetes-native policy engine (no new language to learn)
#      - Validates, mutates, and generates resources
#      - Enforces security policies at admission time
#      - Project: https://kyverno.io / CNCF Incubating
#
#   4. TRIVY OPERATOR (Vulnerability Scanning)
#      - Scans container images for CVEs
#      - Generates Software Bill of Materials (SBOM)
#      - Scans IaC misconfigurations
#      - Project: https://aquasecurity.github.io/trivy-operator
#
#   5. KUBESCAPE (Compliance Scanning)
#      - Scans against NSA, SOC2, MITRE frameworks
#      - Provides actionable remediation guidance
#      - Generates compliance reports for auditors
#      - Project: https://kubescape.io / CNCF Sandbox
#
# PREREQUISITES:
#   - kubectl configured and connected to target cluster
#   - Helm 3.x installed
#   - Cluster should have at least 4GB memory available
#
# USAGE:
#   ./install-security-tools.sh
#
# WHAT HAPPENS:
#   - Helm repositories are added for each tool
#   - Each tool is installed in its own namespace for isolation
#   - Custom values.yaml files are applied for each tool
#   - Installation is verified at the end
#
# ESTIMATED TIME: 5-10 minutes (parallel pod scheduling)
#
# NAMESPACE STRATEGY:
#   Each tool gets its own namespace for:
#   - Security isolation (RBAC scoping)
#   - Resource quota management
#   - Easier cleanup and debugging
#
# ============================================================================

# ----------------------------------------------------------------------------
# BASH STRICT MODE
# ----------------------------------------------------------------------------
# Essential for installation scripts where partial failures could leave
# the cluster in an inconsistent state. If any Helm install fails,
# we stop immediately rather than continuing with a broken setup.
# ----------------------------------------------------------------------------
set -euo pipefail

# ----------------------------------------------------------------------------
# PATH CONFIGURATION
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECURITY_TOOLS_DIR="${SCRIPT_DIR}/../security-tools"

# Terminal colors for readable output
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ----------------------------------------------------------------------------
# PROGRESS TRACKING
# ----------------------------------------------------------------------------
# These variables enable a percentage-based progress indicator.
# For long-running installations, showing progress helps users understand
# how far along the process is and estimate remaining time.
# This follows the requirement to show progress for operations > 2 seconds.
# ----------------------------------------------------------------------------
TOTAL_STEPS=6
CURRENT_STEP=0

# Progress display function - shows step number and percentage
progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local PCT=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo -e "${YELLOW}[${CURRENT_STEP}/${TOTAL_STEPS}] (${PCT}%) $1${NC}"
}

# Script header
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Installing Security Tools${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================
# Quick validation that required tools exist and cluster is accessible.
# We fail fast if prerequisites aren't met to avoid partial installations.
# ============================================================================
command -v helm >/dev/null 2>&1 || { echo -e "${RED}helm not found${NC}"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl not found${NC}"; exit 1; }

# Verify cluster connectivity before attempting installations
# This catches common issues like expired credentials or network problems
kubectl cluster-info >/dev/null 2>&1 || { echo -e "${RED}Cannot connect to cluster${NC}"; exit 1; }

# ============================================================================
# HELM REPOSITORY CONFIGURATION
# ============================================================================
# Each security tool has its own Helm chart repository. We add them all
# upfront and run a single 'repo update' for efficiency.
#
# The '2>/dev/null || true' pattern suppresses errors if repos already exist
# (common when re-running the script) while still catching real failures.
#
# WHY HELM?
#   Helm provides standardized installation, configuration, and upgrades.
#   Each tool's values.yaml in security-tools/ customizes the deployment
#   for this specific demo environment.
# ============================================================================
progress "Adding Helm repositories..."

# Falco Security - runtime threat detection
# Repository contains: falco, falcosidekick, falco-exporter
helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true

# Kyverno - policy engine
# Repository contains: kyverno, kyverno-policies, policy-reporter
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true

# Aqua Security - vulnerability scanning
# Repository contains: trivy, trivy-operator
helm repo add aqua https://aquasecurity.github.io/helm-charts/ 2>/dev/null || true

# Kubescape - compliance scanning
# Repository contains: kubescape-operator
helm repo add kubescape https://kubescape.github.io/helm-charts/ 2>/dev/null || true

# Fetch latest chart versions from all repositories
helm repo update
echo -e "${GREEN}  Helm repos configured${NC}"
echo ""

# ============================================================================
# INSTALL FALCO
# ============================================================================
# Falco is the CORE of runtime threat detection. It monitors:
#   - System calls (via eBPF or kernel module)
#   - Kubernetes audit logs
#   - Cloud provider events
#
# HOW FALCO WORKS:
#   1. Falco runs as a DaemonSet (one pod per node)
#   2. It hooks into the kernel via eBPF (or kernel module as fallback)
#   3. System calls are matched against detection rules
#   4. Matching calls generate security alerts
#
# KEY DETECTION CAPABILITIES:
#   - Shell spawned in container
#   - Sensitive file access (/etc/shadow, /etc/passwd)
#   - Service account token access
#   - Unexpected outbound connections
#   - Privilege escalation attempts
#   - Container escape attempts
#
# The values.yaml configures:
#   - eBPF mode (more compatible with cloud environments)
#   - Custom rules for this demo
#   - Alert output formats
#
# WAIT FLAGS:
#   --wait ensures the deployment is fully ready before proceeding
#   --timeout 5m allows sufficient time for eBPF probe compilation
# ============================================================================
progress "Installing Falco (runtime threat detection)..."
helm upgrade --install falco falcosecurity/falco \
    --namespace falco \
    --create-namespace \
    -f "${SECURITY_TOOLS_DIR}/falco/values.yaml" \
    --wait --timeout 5m
echo -e "${GREEN}  Falco installed${NC}"
echo ""

# ============================================================================
# INSTALL FALCOSIDEKICK
# ============================================================================
# Falcosidekick is an ALERT ROUTER that takes Falco events and forwards
# them to various destinations. In production, this is critical for:
#   - SIEM integration (Splunk, Elastic, Azure Sentinel)
#   - Incident response (PagerDuty, Opsgenie)
#   - Team notification (Slack, Teams, Email)
#   - Metrics/dashboards (Prometheus, Grafana)
#
# WHY SEPARATE FROM FALCO?
#   Separation of concerns - Falco focuses on detection, Falcosidekick
#   handles all the integration complexity. This makes both easier to
#   configure and maintain.
#
# The values.yaml configures output destinations. For this demo:
#   - stdout (for kubectl logs viewing)
#   - UI (web interface for alert visualization)
#
# In production, you'd add:
#   - Azure Sentinel integration
#   - Slack/Teams webhooks
#   - PagerDuty for critical alerts
# ============================================================================
progress "Installing Falcosidekick (alert forwarding)..."
helm upgrade --install falcosidekick falcosecurity/falcosidekick \
    --namespace falco \
    -f "${SECURITY_TOOLS_DIR}/falcosidekick/values.yaml" \
    --wait --timeout 3m
echo -e "${GREEN}  Falcosidekick installed${NC}"
echo ""

# ============================================================================
# INSTALL KYVERNO
# ============================================================================
# Kyverno is a POLICY ENGINE that operates as an admission controller.
# When any resource is created/updated in Kubernetes, Kyverno:
#   1. Intercepts the API request (admission webhook)
#   2. Evaluates applicable policies
#   3. Allows, denies, or mutates the resource
#
# WHY KYVERNO (vs OPA/Gatekeeper)?
#   - Policies are Kubernetes resources (familiar YAML syntax)
#   - No need to learn Rego or other policy languages
#   - Built-in policy library for common use cases
#   - Can both validate AND mutate resources
#
# POLICY MODES:
#   - Enforce: Block non-compliant resources (admission rejection)
#   - Audit: Allow but report violations (for gradual rollout)
#
# KEY POLICIES FOR REGULATED ENVIRONMENTS:
#   - Require non-root containers
#   - Require read-only root filesystem
#   - Require resource limits
#   - Restrict privilege escalation
#   - Require security context
#   - Restrict host namespaces and network
#
# The policies are NOT installed here - they're applied in run-demo.sh
# to demonstrate the before/after compliance state.
# ============================================================================
progress "Installing Kyverno (policy engine)..."
helm upgrade --install kyverno kyverno/kyverno \
    --namespace kyverno \
    --create-namespace \
    -f "${SECURITY_TOOLS_DIR}/kyverno/values.yaml" \
    --wait --timeout 5m
echo -e "${GREEN}  Kyverno installed${NC}"
echo ""

# ============================================================================
# INSTALL TRIVY OPERATOR
# ============================================================================
# Trivy Operator provides CONTINUOUS vulnerability scanning. Unlike
# one-time CI/CD scans, it:
#   1. Watches for new workloads deployed to the cluster
#   2. Scans container images for CVEs automatically
#   3. Stores results as Kubernetes custom resources
#   4. Optionally generates SBOM (Software Bill of Materials)
#
# WHY RUNTIME SCANNING MATTERS:
#   - New vulnerabilities are discovered daily (CVEs)
#   - Images that were "clean" at deploy time may become vulnerable
#   - Operator continuously rescans and updates findings
#   - Provides always-current vulnerability posture
#
# SCAN TYPES:
#   - Vulnerability scanning (CVEs in packages)
#   - Misconfiguration scanning (Dockerfile/K8s issues)
#   - Secret scanning (credentials in images)
#   - SBOM generation (supply chain transparency)
#
# COMPLIANCE VALUE:
#   - DORA requires supply chain visibility
#   - SOC2 requires vulnerability management
#   - SBOM is increasingly required by customers
# ============================================================================
progress "Installing Trivy Operator (vulnerability scanning)..."
helm upgrade --install trivy-operator aqua/trivy-operator \
    --namespace trivy-system \
    --create-namespace \
    -f "${SECURITY_TOOLS_DIR}/trivy/values.yaml" \
    --wait --timeout 5m
echo -e "${GREEN}  Trivy Operator installed${NC}"
echo ""

# ============================================================================
# INSTALL KUBESCAPE
# ============================================================================
# Kubescape provides COMPLIANCE SCANNING against security frameworks:
#   - NSA Kubernetes Hardening Guide
#   - CIS Benchmarks
#   - MITRE ATT&CK
#   - SOC2
#   - Custom frameworks
#
# HOW IT WORKS:
#   1. Scans cluster configuration and workloads
#   2. Evaluates against framework controls
#   3. Calculates compliance percentage
#   4. Provides specific remediation guidance
#
# KEY OUTPUT:
#   - Overall compliance score (e.g., 85% compliant with NSA)
#   - Per-control pass/fail status
#   - Remediation steps for failures
#   - JSON/HTML reports for auditors
#
# WHY KUBESCAPE FOR REGULATED INDUSTRIES:
#   - Maps directly to regulatory requirements
#   - Generates audit-ready evidence
#   - Tracks compliance over time
#   - Integrates with CI/CD for shift-left
#
# The operator runs continuously, updating reports as the cluster changes.
# ============================================================================
progress "Installing Kubescape (compliance scanning)..."
helm upgrade --install kubescape kubescape/kubescape-operator \
    --namespace kubescape \
    --create-namespace \
    -f "${SECURITY_TOOLS_DIR}/kubescape/values.yaml" \
    --wait --timeout 5m
echo -e "${GREEN}  Kubescape installed${NC}"
echo ""

# ============================================================================
# INSTALLATION SUMMARY
# ============================================================================
# Final verification that all tools are running. We check each namespace
# for running pods, which confirms:
#   - Helm install succeeded
#   - Images were pulled successfully
#   - Pods passed health checks
#
# A mismatch between total pods and running pods indicates a problem
# that needs investigation (check pod events with kubectl describe).
# ============================================================================
echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}  All security tools installed (100%)${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "Verifying installations:"
echo ""

# Check pod status in each security namespace
for NS in falco kyverno trivy-system kubescape; do
    PODS=$(kubectl get pods -n "${NS}" --no-headers 2>/dev/null | wc -l)
    READY=$(kubectl get pods -n "${NS}" --no-headers 2>/dev/null | grep -c "Running" || true)
    echo "  ${NS}: ${READY}/${PODS} pods running"
done

echo ""
echo "Next step: Deploy demo workloads or run the demo"
echo "  ./run-demo.sh"
