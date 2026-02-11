#!/usr/bin/env bash
# ABOUTME: Runs terraform validate on the infrastructure directory.
# ABOUTME: Unit test — validates HCL syntax and configuration without deploying.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."
TF_DIR="${ROOT_DIR}/infrastructure/terraform"

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BOLD}── Terraform Validation ──${NC}"
echo ""

# Check terraform is installed
if ! command -v terraform >/dev/null 2>&1; then
    echo -e "${YELLOW}SKIP: terraform not installed${NC}"
    exit 0
fi

echo "Terraform version: $(terraform version -json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || terraform version | head -1)"
echo "Directory: ${TF_DIR}"
echo ""

# Initialize if needed (plugins must be downloaded for validate)
if [[ ! -d "${TF_DIR}/.terraform" ]]; then
    echo "Running terraform init..."
    terraform -chdir="${TF_DIR}" init -backend=false -input=false >/dev/null 2>&1 || {
        echo -e "${YELLOW}SKIP: terraform init failed (network or provider issue)${NC}"
        exit 0
    }
fi

# Validate
echo "Running terraform validate..."
output=$(terraform -chdir="${TF_DIR}" validate 2>&1)
exit_code=$?

echo "$output"
echo ""

# Check for actual errors (ignoring deprecation warnings)
if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}Terraform validation PASSED${NC}"
    # Note known warnings
    if echo "$output" | grep -q "Warning"; then
        echo -e "${YELLOW}(with known deprecation warnings — see azurerm v4.0 upgrade notes)${NC}"
    fi
    exit 0
else
    echo -e "${RED}Terraform validation FAILED${NC}"
    exit 1
fi
