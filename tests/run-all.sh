#!/usr/bin/env bash
# ABOUTME: Orchestrates all test suites: unit, integration, and e2e.
# ABOUTME: Supports --unit, --integration, --e2e, or --all (default: unit only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Argument parsing
RUN_UNIT=false
RUN_INTEGRATION=false
RUN_E2E=false

if [[ $# -eq 0 ]]; then
    # Default: run unit tests only (safe without cluster)
    RUN_UNIT=true
fi

for arg in "$@"; do
    case "$arg" in
        --unit)        RUN_UNIT=true ;;
        --integration) RUN_INTEGRATION=true ;;
        --e2e)         RUN_E2E=true ;;
        --all)         RUN_UNIT=true; RUN_INTEGRATION=true; RUN_E2E=true ;;
        --help|-h)
            echo "Usage: run-all.sh [--unit] [--integration] [--e2e] [--all]"
            echo ""
            echo "  --unit         Run unit tests (no cluster needed)"
            echo "  --integration  Run integration tests (needs cluster)"
            echo "  --e2e          Run end-to-end tests (needs cluster + tools)"
            echo "  --all          Run all test suites"
            echo ""
            echo "Default (no args): --unit"
            exit 0
            ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

total_passed=0
total_failed=0
suites_run=0
suite_results=()

run_suite() {
    local name="$1"
    local script="$2"

    echo ""
    echo -e "${BOLD}════════════════════════════════════════${NC}"
    echo -e "${BOLD}  ${name}${NC}"
    echo -e "${BOLD}════════════════════════════════════════${NC}"
    echo ""

    if [[ ! -x "$script" ]]; then
        chmod +x "$script"
    fi

    if "$script"; then
        suite_results+=("${GREEN}PASS${NC} ${name}")
    else
        suite_results+=("${RED}FAIL${NC} ${name}")
        total_failed=$((total_failed + 1))
    fi
    suites_run=$((suites_run + 1))
}

echo -e "${BOLD}╔═══════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  AKS Regulated Enterprise Test Suite  ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════╝${NC}"

# Unit tests
if [[ "$RUN_UNIT" == "true" ]]; then
    run_suite "Unit: YAML Syntax" "${SCRIPT_DIR}/unit/test-yaml-syntax.sh"
    run_suite "Unit: Shell Syntax" "${SCRIPT_DIR}/unit/test-shell-syntax.sh"
    run_suite "Unit: Terraform Validate" "${SCRIPT_DIR}/unit/test-terraform-validate.sh"
    # Helm template requires network (repo update) — run if helm is available
    if command -v helm >/dev/null 2>&1; then
        run_suite "Unit: Helm Template" "${SCRIPT_DIR}/unit/test-helm-template.sh"
    fi
fi

# Integration tests
if [[ "$RUN_INTEGRATION" == "true" ]]; then
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "\n${YELLOW}SKIP: Integration tests require a running cluster${NC}"
    else
        run_suite "Integration: Tier 1 (Security)" "${SCRIPT_DIR}/integration/test-tier1.sh"
        run_suite "Integration: Tier 2 (Observability)" "${SCRIPT_DIR}/integration/test-tier2.sh"
        run_suite "Integration: Tier 3 (Platform)" "${SCRIPT_DIR}/integration/test-tier3.sh"
    fi
fi

# E2E tests
if [[ "$RUN_E2E" == "true" ]]; then
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "\n${YELLOW}SKIP: E2E tests require a running cluster${NC}"
    else
        run_suite "E2E: Attack-Detect-Prevent" "${SCRIPT_DIR}/e2e/test-attack-scenario.sh"
        run_suite "E2E: GitOps Delivery" "${SCRIPT_DIR}/e2e/test-gitops-scenario.sh"
        run_suite "E2E: Zero-Trust" "${SCRIPT_DIR}/e2e/test-zerotrust-scenario.sh"
    fi
fi

# Summary
echo ""
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo -e "${BOLD}  Test Suite Summary${NC}"
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo ""

for result in "${suite_results[@]}"; do
    echo -e "  ${result}"
done

echo ""
echo "  Suites run: ${suites_run}"
echo ""

if [[ $total_failed -gt 0 ]]; then
    echo -e "${RED}${total_failed} suite(s) FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All ${suites_run} suite(s) PASSED${NC}"
    exit 0
fi
