#!/usr/bin/env bash
# ABOUTME: Validates shell script syntax using bash -n and shellcheck (if available).
# ABOUTME: Unit test — checks all .sh files for syntax errors without executing them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0
errors=()

echo -e "${BOLD}── Shell Script Syntax Validation ──${NC}"
echo ""

# Find all .sh files
shell_files=$(find "${ROOT_DIR}" -name "*.sh" | grep -v '.git/' | grep -v '.terraform/' | sort)
total=$(echo "$shell_files" | wc -l)

echo "Found ${total} shell scripts to validate"
echo ""

# Phase 1: bash -n (syntax check)
echo -e "${BOLD}Phase 1: bash -n (syntax check)${NC}"
echo ""

for file in $shell_files; do
    relative_path="${file#${ROOT_DIR}/}"

    if bash -n "$file" 2>/dev/null; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        error_msg=$(bash -n "$file" 2>&1 | head -3)
        errors+=("  FAIL: ${relative_path}")
        errors+=("        ${error_msg}")
    fi
done

echo -e "  ${GREEN}Passed: ${passed}${NC} / ${total}"
if [[ $failed -gt 0 ]]; then
    echo -e "  ${RED}Failed: ${failed}${NC}"
fi
echo ""

# Phase 2: shellcheck (if available)
if command -v shellcheck >/dev/null 2>&1; then
    echo -e "${BOLD}Phase 2: shellcheck (linting)${NC}"
    echo ""

    sc_passed=0
    sc_warnings=0

    for file in $shell_files; do
        relative_path="${file#${ROOT_DIR}/}"

        # Run shellcheck with common exclusions for this project style
        # SC1090: Can't follow non-constant source
        # SC1091: Not following sourced file
        # SC2016: Single-quoted expansion (intentional in kubectl exec commands)
        # SC2034: Variable appears unused (common with sourced libs)
        # SC2155: Declare and assign separately
        if shellcheck -e SC1090,SC1091,SC2016,SC2034,SC2155 "$file" >/dev/null 2>&1; then
            sc_passed=$((sc_passed + 1))
        else
            sc_warnings=$((sc_warnings + 1))
            # Don't fail on shellcheck warnings, just report
            echo -e "  ${YELLOW}WARN${NC} ${relative_path}"
            shellcheck -e SC1090,SC1091,SC2016,SC2034,SC2155 -f gcc "$file" 2>&1 | head -5 || true
        fi
    done

    echo ""
    echo -e "  ${GREEN}Clean: ${sc_passed}${NC}, ${YELLOW}Warnings: ${sc_warnings}${NC}"
    echo ""
else
    echo -e "${YELLOW}shellcheck not installed — skipping lint phase${NC}"
    echo "  Install: apt install shellcheck  OR  brew install shellcheck"
    echo ""
fi

# Print results
echo -e "${BOLD}── Results ──${NC}"
echo ""

if [[ ${#errors[@]} -gt 0 ]]; then
    echo -e "${RED}Syntax Errors:${NC}"
    for err in "${errors[@]}"; do
        echo "$err"
    done
    echo ""
fi

if [[ $failed -gt 0 ]]; then
    echo -e "${RED}Shell syntax validation FAILED (${failed} errors)${NC}"
    exit 1
else
    echo -e "${GREEN}All shell scripts are syntactically valid${NC}"
    exit 0
fi
