#!/usr/bin/env bash
# ABOUTME: Orchestrates the full zero-trust networking scenario with pauses for narration.
# ABOUTME: Runs all four steps in sequence demonstrating defense-in-depth security.
# ============================================================================
#
# ZERO-TRUST NETWORKING SCENARIO — FULL DEMO ORCHESTRATOR
#
# This script runs the complete zero-trust scenario with pauses
# between each step for presenter narration:
#
#   Step 1: Deploy mesh-enabled multi-service application
#   Step 2: Enforce mutual TLS (encrypt all traffic)
#   Step 3: Apply authorization policies (identity-based access)
#   Step 4: Apply network policies (L3/L4 isolation)
#
# TIMING (approximate):
#   - Introduction: 2 minutes
#   - Step 1 (Deploy mesh): 5 minutes
#   - Step 2 (mTLS): 5 minutes
#   - Step 3 (AuthZ): 7 minutes
#   - Step 4 (NetPol): 5 minutes
#   - Summary: 3 minutes
#   Total: ~27 minutes
#
# USAGE:
#   ./run-demo.sh              # Full interactive demo
#   ./run-demo.sh --step=1     # Run only step 1
#   ./run-demo.sh --step=2     # Run only step 2
#   ./run-demo.sh --step=3     # Run only step 3
#   ./run-demo.sh --step=4     # Run only step 4
#   ./run-demo.sh --cleanup    # Remove all demo resources
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

DEMO_NS="zero-trust-demo"

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
            echo "Usage: run-demo.sh [--step=1|2|3|4] [--cleanup]"
            echo ""
            echo "Options:"
            echo "  --step=N    Run only step N (1, 2, 3, or 4)"
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
    echo -e "${BOLD}── Zero-Trust Demo Cleanup ──${NC}"
    echo ""

    info "Removing demo namespace and all resources..."
    kubectl delete namespace "${DEMO_NS}" --wait=false 2>/dev/null || true

    info "Removing mesh-wide PeerAuthentication..."
    kubectl delete peerauthentication default -n istio-system 2>/dev/null || true

    success "Zero-trust demo resources cleaned up"
    info "Note: Istio control plane remains (managed by install-tools.sh)"
    exit 0
fi

# ----------------------------------------------------------------------------
# INTRODUCTION
# ----------------------------------------------------------------------------
if [[ -z "$STEP" || "$STEP" == "1" ]]; then
    echo -e "${BOLD}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  Zero-Trust Networking Demo               ║${NC}"
    echo -e "${BOLD}║  Istio + NetworkPolicy + Falco            ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo "This demo builds four layers of zero-trust security:"
    echo ""
    echo "  1. ${GREEN}Service Mesh${NC}  — Envoy sidecars for every pod"
    echo "  2. ${GREEN}Mutual TLS${NC}    — Encrypt all pod-to-pod traffic"
    echo "  3. ${GREEN}Authorization${NC} — Identity-based L7 access control"
    echo "  4. ${GREEN}Network Policy${NC} — L3/L4 microsegmentation"
    echo ""
    echo -e "${YELLOW}Zero-trust principle:${NC} Never trust, always verify."
    echo "  No implicit trust between services, even within the same cluster."
    echo ""
    echo -e "${YELLOW}Regulatory alignment:${NC}"
    echo "  - NIST 800-207: Zero Trust Architecture"
    echo "  - PCI-DSS 4.1: Encrypt data in transit"
    echo "  - DORA Article 9: Network segmentation"
    echo "  - NCUA Part 748: Data protection controls"
    echo ""

    if [[ -z "$STEP" ]]; then
        pause
    fi
fi

# ----------------------------------------------------------------------------
# STEP 1: DEPLOY MESH
# ----------------------------------------------------------------------------
if [[ -z "$STEP" || "$STEP" == "1" ]]; then
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  STEP 1: Deploy Mesh-Enabled Application${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Deploy a three-tier app (frontend → backend → database)"
    echo "with Envoy sidecars injected automatically by Istio."
    echo ""

    if [[ -z "$STEP" ]]; then
        pause
    fi

    "${SCRIPT_DIR}/01-deploy-mesh.sh"

    if [[ -z "$STEP" ]]; then
        pause
    fi
fi

# ----------------------------------------------------------------------------
# STEP 2: ENFORCE mTLS
# ----------------------------------------------------------------------------
if [[ -z "$STEP" || "$STEP" == "2" ]]; then
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  STEP 2: Enforce Mutual TLS${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "STRICT mTLS ensures every connection is encrypted and"
    echo "authenticated with SPIFFE certificates. Plaintext is rejected."
    echo ""

    if [[ -z "$STEP" ]]; then
        pause
    fi

    "${SCRIPT_DIR}/02-enforce-mtls.sh"

    if [[ -z "$STEP" ]]; then
        pause
    fi
fi

# ----------------------------------------------------------------------------
# STEP 3: AUTHORIZATION POLICIES
# ----------------------------------------------------------------------------
if [[ -z "$STEP" || "$STEP" == "3" ]]; then
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  STEP 3: Service Authorization${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Default-deny + explicit allow rules enforce the service"
    echo "graph. Only authorized SPIFFE identities can communicate."
    echo ""

    if [[ -z "$STEP" ]]; then
        pause
    fi

    "${SCRIPT_DIR}/03-authorization-policies.sh"

    if [[ -z "$STEP" ]]; then
        pause
    fi
fi

# ----------------------------------------------------------------------------
# STEP 4: NETWORK POLICIES
# ----------------------------------------------------------------------------
if [[ -z "$STEP" || "$STEP" == "4" ]]; then
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  STEP 4: Network Isolation${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Kubernetes NetworkPolicies add L3/L4 isolation below the"
    echo "Istio mesh. Even if Istio is bypassed, the CNI blocks traffic."
    echo ""

    if [[ -z "$STEP" ]]; then
        pause
    fi

    "${SCRIPT_DIR}/04-network-policies.sh"

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
    echo -e "${GREEN}Zero-Trust Defense-in-Depth Summary:${NC}"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────┐"
    echo "  │ Layer              │ Tool              │ Blocks              │"
    echo "  ├────────────────────────────────────────────────────────────┤"
    echo "  │ L7 Authorization   │ Istio AuthzPolicy │ Unauthorized calls  │"
    echo "  │ mTLS Encryption    │ Istio PeerAuth    │ Plaintext traffic   │"
    echo "  │ L3/L4 Isolation    │ NetworkPolicy     │ Network-level       │"
    echo "  │ Runtime Detection  │ Falco             │ Policy bypass       │"
    echo "  └────────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "${YELLOW}Key takeaway:${NC}"
    echo "  Four independent security layers, each with its own control"
    echo "  plane. Compromise of one layer does not compromise the others."
    echo ""
    echo -e "${BOLD}All tools are CNCF projects, open source, and production-ready.${NC}"
    echo ""
    echo "Cleanup: ./run-demo.sh --cleanup"
fi
