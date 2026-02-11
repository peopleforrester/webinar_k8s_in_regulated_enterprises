#!/usr/bin/env bash
# ABOUTME: Validates YAML syntax across all YAML files in the repository.
# ABOUTME: Unit test — runs without a cluster. Uses yamllint if available, falls back to python.
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
skipped=0
errors=()

echo -e "${BOLD}── YAML Syntax Validation ──${NC}"
echo ""

# Find all YAML files (excluding .git, node_modules, .terraform, Helm templates)
yaml_files=$(find "${ROOT_DIR}" \
    \( -name "*.yaml" -o -name "*.yml" \) \
    | grep -v '.git/' \
    | grep -v 'node_modules/' \
    | grep -v '.terraform/' \
    | grep -v '/templates/' \
    | sort)

total=$(echo "$yaml_files" | wc -l)
echo "Found ${total} YAML files to validate"
echo ""

# Choose validator
if command -v yamllint >/dev/null 2>&1; then
    VALIDATOR="yamllint"
    echo "Using: yamllint"
elif command -v python3 >/dev/null 2>&1; then
    VALIDATOR="python3"
    echo "Using: python3 yaml.safe_load"
else
    echo -e "${RED}No YAML validator found. Install yamllint or python3 with PyYAML.${NC}"
    exit 1
fi
echo ""

for file in $yaml_files; do
    relative_path="${file#${ROOT_DIR}/}"

    if [[ "$VALIDATOR" == "yamllint" ]]; then
        # Relaxed yamllint config: allow long lines, trailing spaces
        if yamllint -d "{extends: relaxed, rules: {line-length: disable, truthy: disable, document-start: disable}}" "$file" >/dev/null 2>&1; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
            errors+=("  FAIL: ${relative_path}")
            error_detail=$(yamllint -d "{extends: relaxed, rules: {line-length: disable, truthy: disable, document-start: disable}}" "$file" 2>&1 | head -3 || true)
            if [[ -n "$error_detail" ]]; then
                errors+=("        ${error_detail}")
            fi
        fi
    else
        # Python-based validation
        if python3 -c "
import yaml, sys
try:
    with open('${file}') as f:
        list(yaml.safe_load_all(f))
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
            errors+=("  FAIL: ${relative_path}")
        fi
    fi
done

# Print results
echo ""
echo -e "${BOLD}── Results ──${NC}"
echo ""
echo -e "  ${GREEN}Passed: ${passed}${NC}"
echo -e "  ${RED}Failed: ${failed}${NC}"
echo "  Total:  ${total}"
echo ""

if [[ ${#errors[@]} -gt 0 ]]; then
    echo -e "${RED}Failures:${NC}"
    for err in "${errors[@]}"; do
        echo "$err"
    done
    echo ""
fi

if [[ $failed -gt 0 ]]; then
    echo -e "${RED}YAML syntax validation FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All YAML files are syntactically valid${NC}"
    exit 0
fi
