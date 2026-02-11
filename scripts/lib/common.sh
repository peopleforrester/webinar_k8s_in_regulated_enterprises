#!/usr/bin/env bash
# ABOUTME: Shared functions for the tiered install system (colors, progress, helm helpers).
# ABOUTME: Sourced by install-tools.sh and tier-specific library scripts.
# ============================================================================
#
# This library provides common utilities used across all install tiers:
#   - Terminal colors and output helpers
#   - Progress tracking with percentage display
#   - Helm install wrapper with consistent error handling
#   - Pod health verification
#   - Prerequisite checks (helm, kubectl, cluster connectivity)
#
# USAGE:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# ============================================================================

# Guard against double-sourcing
if [[ -n "${_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi
_COMMON_SH_LOADED=1

# ----------------------------------------------------------------------------
# TERMINAL COLORS
# ----------------------------------------------------------------------------
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ----------------------------------------------------------------------------
# PATH CONFIGURATION
# ----------------------------------------------------------------------------
# These are set once and available to all sourcing scripts.
# SCRIPT_DIR points to the scripts/ directory regardless of which lib file
# is sourced first.
# ----------------------------------------------------------------------------
COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${COMMON_LIB_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOLS_DIR="${ROOT_DIR}/tools"

# ----------------------------------------------------------------------------
# PROGRESS TRACKING
# ----------------------------------------------------------------------------
# TOTAL_STEPS and CURRENT_STEP are managed by the calling script.
# Call set_total_steps() before using progress().
# ----------------------------------------------------------------------------
TOTAL_STEPS=0
CURRENT_STEP=0

set_total_steps() {
    TOTAL_STEPS="$1"
    CURRENT_STEP=0
}

progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local pct=0
    if [[ $TOTAL_STEPS -gt 0 ]]; then
        pct=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    fi
    echo -e "${YELLOW}[${CURRENT_STEP}/${TOTAL_STEPS}] (${pct}%) $1${NC}"
}

# ----------------------------------------------------------------------------
# OUTPUT HELPERS
# ----------------------------------------------------------------------------
info()    { echo -e "${CYAN}  $*${NC}"; }
success() { echo -e "${GREEN}  $*${NC}"; }
warn()    { echo -e "${YELLOW}  WARNING: $*${NC}"; }
error()   { echo -e "${RED}  ERROR: $*${NC}"; }

# ----------------------------------------------------------------------------
# INSTALL FAILURE TRACKING
# ----------------------------------------------------------------------------
INSTALL_FAILURES=()

record_failure() {
    INSTALL_FAILURES+=("$1")
}

has_failures() {
    [[ ${#INSTALL_FAILURES[@]} -gt 0 ]]
}

get_failures() {
    echo "${INSTALL_FAILURES[*]}"
}

# ----------------------------------------------------------------------------
# PREREQUISITE CHECKS
# ----------------------------------------------------------------------------
# Validates that required CLI tools exist and the cluster is reachable.
# Call this before any install operations.
# ----------------------------------------------------------------------------
check_prerequisites() {
    command -v helm >/dev/null 2>&1 || { error "helm not found. Install from https://helm.sh"; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { error "kubectl not found"; exit 1; }
    kubectl cluster-info >/dev/null 2>&1 || { error "Cannot connect to cluster. Check kubeconfig."; exit 1; }
    success "Prerequisites OK (helm, kubectl, cluster reachable)"
}

# ----------------------------------------------------------------------------
# HEALTH CHECK FUNCTION
# ----------------------------------------------------------------------------
# Verifies pods in a namespace are running after Helm install.
# Waits up to 60s for pods to stabilize, then reports status.
# If pods are in CrashLoopBackOff or Error, prints logs and flags failure.
#
# Args:
#   $1 - namespace
#   $2 - tool display name
# Returns:
#   0 if healthy, 1 if failed (also records failure)
# ----------------------------------------------------------------------------
verify_install() {
    local namespace="$1"
    local tool_name="$2"
    local max_wait=60
    local elapsed=0

    echo -e "  Verifying ${tool_name} pods..."

    # Wait for pods to exist
    while [[ $(kubectl get pods -n "${namespace}" --no-headers 2>/dev/null | wc -l) -eq 0 ]] && [[ $elapsed -lt 15 ]]; do
        sleep 3
        elapsed=$((elapsed + 3))
    done

    # Wait for pods to stabilize
    elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        local crash_pods
        crash_pods=$(kubectl get pods -n "${namespace}" --no-headers 2>/dev/null | grep -E "CrashLoopBackOff|Error|ImagePullBackOff" | wc -l)
        local not_ready
        not_ready=$(kubectl get pods -n "${namespace}" --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)

        if [[ $crash_pods -gt 0 ]]; then
            echo -e "${RED}  FAILED: ${tool_name} has pods in error state!${NC}"
            echo ""
            kubectl get pods -n "${namespace}" --no-headers 2>/dev/null | grep -E "CrashLoopBackOff|Error|ImagePullBackOff" | while read -r line; do
                local pod_name
                pod_name=$(echo "$line" | awk '{print $1}')
                echo -e "${RED}  Pod: ${pod_name}${NC}"
                echo -e "${RED}  Status: $(echo "$line" | awk '{print $3}')${NC}"
                echo -e "${RED}  Logs (last 5 lines):${NC}"
                kubectl logs -n "${namespace}" "${pod_name}" --tail=5 2>&1 | sed 's/^/    /'
                echo ""
            done
            record_failure "${tool_name}"
            return 1
        fi

        if [[ $not_ready -eq 0 ]]; then
            local total
            total=$(kubectl get pods -n "${namespace}" --no-headers 2>/dev/null | wc -l)
            local running
            running=$(kubectl get pods -n "${namespace}" --no-headers 2>/dev/null | grep -c "Running" || true)
            echo -e "${GREEN}  ${tool_name}: ${running}/${total} pods running${NC}"
            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo -e "${RED}  WARNING: ${tool_name} pods not fully ready after ${max_wait}s${NC}"
    kubectl get pods -n "${namespace}" --no-headers 2>/dev/null | sed 's/^/    /'
    record_failure "${tool_name}"
    return 1
}

# ----------------------------------------------------------------------------
# HELM INSTALL WRAPPER
# ----------------------------------------------------------------------------
# Standardized Helm upgrade --install with consistent flags.
# Adds repo if needed, then installs with values file.
#
# Args:
#   $1 - release name
#   $2 - chart reference (e.g., falcosecurity/falco)
#   $3 - namespace
#   $4 - values file path (relative to TOOLS_DIR)
#   $5 - timeout (default: 5m)
#   $6+ - extra helm flags (optional)
# ----------------------------------------------------------------------------
helm_install() {
    local release="$1"
    local chart="$2"
    local namespace="$3"
    local values_file="$4"
    local timeout="${5:-5m}"
    shift 5 2>/dev/null || shift $#

    local cmd=(helm upgrade --install "${release}" "${chart}"
        --namespace "${namespace}"
        --create-namespace
        --wait --timeout "${timeout}")

    if [[ -n "${values_file}" && -f "${values_file}" ]]; then
        cmd+=(-f "${values_file}")
    fi

    # Append any extra flags
    if [[ $# -gt 0 ]]; then
        cmd+=("$@")
    fi

    "${cmd[@]}"
}

# ----------------------------------------------------------------------------
# HELM REPO HELPERS
# ----------------------------------------------------------------------------
# Adds a Helm repo idempotently (suppresses "already exists" errors).
# ----------------------------------------------------------------------------
helm_repo_add() {
    local name="$1"
    local url="$2"
    helm repo add "${name}" "${url}" 2>/dev/null || true
}

# ----------------------------------------------------------------------------
# NAMESPACE STATUS CHECK
# ----------------------------------------------------------------------------
# Prints pod status for a given namespace. Used in summaries.
#
# Args:
#   $1 - namespace
# Returns:
#   Prints colored status line
# ----------------------------------------------------------------------------
print_namespace_status() {
    local ns="$1"
    local pods running failed

    pods=$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null | wc -l)
    running=$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null | grep -c "Running" || true)
    failed=$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null | grep -cE "CrashLoopBackOff|Error|ImagePullBackOff" || true)

    if [[ $failed -gt 0 ]]; then
        echo -e "  ${RED}FAIL  ${ns}: ${running}/${pods} running, ${failed} failed${NC}"
    elif [[ $pods -eq 0 ]]; then
        echo -e "  ${YELLOW}SKIP  ${ns}: no pods found${NC}"
    else
        echo -e "  ${GREEN}OK    ${ns}: ${running}/${pods} pods running${NC}"
    fi
}
