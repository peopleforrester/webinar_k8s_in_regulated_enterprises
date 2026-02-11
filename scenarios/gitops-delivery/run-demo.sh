#!/usr/bin/env bash
# ABOUTME: Orchestrates the full GitOps delivery scenario with pauses for narration.
# ABOUTME: Runs all three steps in sequence with guided commentary for demos.
# ============================================================================
#
# GITOPS DELIVERY SCENARIO — FULL DEMO ORCHESTRATOR
#
# This script runs the complete GitOps delivery scenario with pauses
# between each step for presenter narration:
#
#   Step 1: Setup ArgoCD Application (Git → Cluster reconciliation)
#   Step 2: Trigger Sync (Git commit → automated deployment)
#   Step 3: Vulnerable Image Gate (Trivy + Kyverno security pipeline)
#
# TIMING (approximate):
#   - Introduction: 2 minutes
#   - Step 1 (ArgoCD setup): 5 minutes
#   - Step 2 (GitOps sync): 5 minutes
#   - Step 3 (Image scanning): 5 minutes
#   - Summary: 3 minutes
#   Total: ~20 minutes
#
# DEMO TIPS:
#   - Have ArgoCD UI open (kubectl port-forward svc/argocd-server -n argocd 8080:443)
#   - Have a browser tab for the ArgoCD dashboard
#   - Practice the timing beforehand
#   - Know the regulatory talking points for your audience
#
# USAGE:
#   ./run-demo.sh              # Full interactive demo
#   ./run-demo.sh --step=1     # Run only step 1
#   ./run-demo.sh --step=2     # Run only step 2
#   ./run-demo.sh --step=3     # Run only step 3
#   ./run-demo.sh --cleanup    # Remove all demo resources
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
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}  ℹ ${NC} $*"; }
success() { echo -e "${GREEN}  ✓ ${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠ ${NC} $*"; }

pause() {
    echo ""
    echo -e "${BLUE}  Press Enter to continue...${NC}"
    read -r
}

# ----------------------------------------------------------------------------
# ARGUMENT PARSING
# ----------------------------------------------------------------------------
STEP=""
CLEANUP=false

for arg in "$@"; do
    case "$arg" in
        --step=*)
            STEP="${arg#--step=}"
            ;;
        --cleanup)
            CLEANUP=true
            ;;
        --help|-h)
            echo "Usage: run-demo.sh [--step=1|2|3] [--cleanup]"
            echo ""
            echo "Options:"
            echo "  --step=N    Run only step N (1, 2, or 3)"
            echo "  --cleanup   Remove all demo resources"
            echo "  --help      Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# ----------------------------------------------------------------------------
# CLEANUP MODE
# ----------------------------------------------------------------------------
if [[ "$CLEANUP" == "true" ]]; then
    echo -e "${BOLD}── GitOps Demo Cleanup ──${NC}"
    echo ""

    info "Removing ArgoCD Application..."
    kubectl delete application demo-app-production -n argocd 2>/dev/null || true

    info "Removing test namespace..."
    kubectl delete namespace vuln-image-test --wait=false 2>/dev/null || true
    kubectl delete namespace demo-app --wait=false 2>/dev/null || true

    info "Removing AppProject..."
    kubectl delete appproject regulated-apps -n argocd 2>/dev/null || true

    success "GitOps demo resources cleaned up"
    exit 0
fi

# ----------------------------------------------------------------------------
# INTRODUCTION
# ----------------------------------------------------------------------------
if [[ -z "$STEP" || "$STEP" == "1" ]]; then
    echo -e "${BOLD}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  GitOps Delivery Pipeline Demo            ║${NC}"
    echo -e "${BOLD}║  ArgoCD → Kustomize → Trivy               ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo "This demo shows a complete GitOps delivery pipeline for"
    echo "regulated enterprises using three CNCF tools:"
    echo ""
    echo "  1. ${GREEN}ArgoCD${NC}    — Git-based deployment with full audit trail"
    echo "  2. ${GREEN}Kustomize${NC} — Environment separation without template duplication"
    echo "  3. ${GREEN}Trivy${NC}     — Continuous vulnerability scanning for deployed images"
    echo ""
    echo -e "${YELLOW}Regulatory alignment:${NC}"
    echo "  - NCUA/FFIEC: Change management via version-controlled deployments"
    echo "  - DORA Article 9: ICT change management with automated audit trail"
    echo "  - PCI-DSS 6.4: Separate environments (dev/staging/prod overlays)"
    echo "  - SOC 2 CC8.1: All changes tracked and approved in Git"
    echo ""

    if [[ -z "$STEP" ]]; then
        pause
    fi
fi

# ----------------------------------------------------------------------------
# STEP 1: SETUP ARGOCD APPLICATION
# ----------------------------------------------------------------------------
if [[ -z "$STEP" || "$STEP" == "1" ]]; then
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  STEP 1: ArgoCD Application Setup${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "ArgoCD watches a Git repository and automatically deploys"
    echo "changes to the cluster. The Application CRD defines what"
    echo "to deploy (kustomize overlay) and where (target namespace)."
    echo ""

    if [[ -z "$STEP" ]]; then
        pause
    fi

    "${SCRIPT_DIR}/01-setup-argocd-app.sh"

    if [[ -z "$STEP" ]]; then
        pause
    fi
fi

# ----------------------------------------------------------------------------
# STEP 2: TRIGGER GITOPS SYNC
# ----------------------------------------------------------------------------
if [[ -z "$STEP" || "$STEP" == "2" ]]; then
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  STEP 2: Git-Driven Deployment${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "We modify the kustomize overlay in Git. ArgoCD detects the"
    echo "change and syncs the cluster to match. No manual kubectl."
    echo "Every change has a Git commit for the audit trail."
    echo ""

    if [[ -z "$STEP" ]]; then
        pause
    fi

    "${SCRIPT_DIR}/02-trigger-sync.sh"

    if [[ -z "$STEP" ]]; then
        pause
    fi
fi

# ----------------------------------------------------------------------------
# STEP 3: VULNERABLE IMAGE GATE
# ----------------------------------------------------------------------------
if [[ -z "$STEP" || "$STEP" == "3" ]]; then
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  STEP 3: Supply Chain Security Gate${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Even with GitOps, a vulnerable image can reach the cluster."
    echo "Trivy Operator scans every deployed image and generates"
    echo "VulnerabilityReports that can gate future deployments."
    echo ""

    if [[ -z "$STEP" ]]; then
        pause
    fi

    "${SCRIPT_DIR}/03-vulnerable-image-gate.sh"

    if [[ -z "$STEP" ]]; then
        pause
    fi
fi

# ----------------------------------------------------------------------------
# SUMMARY
# ----------------------------------------------------------------------------
if [[ -z "$STEP" ]]; then
    echo -e "${BOLD}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  DEMO COMPLETE                            ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}GitOps Delivery Pipeline Summary:${NC}"
    echo ""
    echo "  1. DEPLOY  — ArgoCD syncs kustomize overlays from Git"
    echo "  2. CHANGE  — Git commits trigger automated deployments"
    echo "  3. SECURE  — Trivy scans images, Kyverno enforces policies"
    echo ""
    echo -e "${YELLOW}Regulatory value:${NC}"
    echo "  - Every deployment traceable to a Git commit (NCUA, DORA)"
    echo "  - Environment separation via kustomize overlays (PCI-DSS)"
    echo "  - Continuous vulnerability scanning (DORA Article 6)"
    echo "  - Policy enforcement prevents insecure deployments (SOC 2)"
    echo ""
    echo -e "${BOLD}All tools are CNCF projects, open source, and production-ready.${NC}"
    echo ""
    echo "Cleanup: ./run-demo.sh --cleanup"
fi
