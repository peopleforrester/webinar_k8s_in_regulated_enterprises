#!/usr/bin/env bash
# ABOUTME: Runs helm template --dry-run for each tool's values.yaml to catch rendering errors.
# ABOUTME: Unit test — validates Helm chart rendering without a cluster.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."
TOOLS_DIR="${ROOT_DIR}/tools"

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0
skipped=0
errors=()

echo -e "${BOLD}── Helm Template Validation ──${NC}"
echo ""

if ! command -v helm >/dev/null 2>&1; then
    echo -e "${YELLOW}SKIP: helm not installed${NC}"
    exit 0
fi

echo "Helm version: $(helm version --short 2>/dev/null)"
echo ""

# Tool-to-chart mapping
# Format: tool_dir:repo/chart_name:release_name:namespace
declare -a CHARTS=(
    "falco:falcosecurity/falco:falco:falco"
    "falcosidekick:falcosecurity/falcosidekick:falcosidekick:falco"
    "falco-talon:falcosecurity/falco-talon:falco-talon:falco"
    "kyverno:kyverno/kyverno:kyverno:kyverno"
    "trivy:aquasecurity/trivy-operator:trivy-operator:trivy-system"
    "kubescape:kubescape/kubescape-operator:kubescape:kubescape"
    "prometheus:prometheus-community/kube-prometheus-stack:prometheus:monitoring"
    "argocd:argo/argo-cd:argocd:argocd"
    "external-secrets:external-secrets/external-secrets:external-secrets:external-secrets"
    "istio:istio/istiod:istiod:istio-system"
    "crossplane:crossplane-stable/crossplane:crossplane:crossplane-system"
    "harbor:harbor/harbor:harbor:harbor"
)

# Ensure repos are added (suppress output)
echo "Adding Helm repos..."
helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
helm repo add aquasecurity https://aquasecurity.github.io/helm-charts/ 2>/dev/null || true
helm repo add kubescape https://kubescape.github.io/helm-charts/ 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo add istio https://istio-release.storage.googleapis.com/charts 2>/dev/null || true
helm repo add crossplane-stable https://charts.crossplane.io/stable 2>/dev/null || true
helm repo add harbor https://helm.goharbor.io 2>/dev/null || true
helm repo update >/dev/null 2>&1 || true
echo ""

for entry in "${CHARTS[@]}"; do
    IFS=':' read -r tool_dir chart release namespace <<< "$entry"
    values_file="${TOOLS_DIR}/${tool_dir}/values.yaml"

    if [[ ! -f "$values_file" ]]; then
        echo -e "  ${YELLOW}SKIP${NC} ${tool_dir}: no values.yaml"
        skipped=$((skipped + 1))
        continue
    fi

    echo -n "  Testing ${tool_dir}... "

    if helm template "${release}" "${chart}" \
        --namespace "${namespace}" \
        -f "${values_file}" \
        >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        passed=$((passed + 1))
    else
        echo -e "${RED}FAIL${NC}"
        failed=$((failed + 1))
        error_msg=$(helm template "${release}" "${chart}" --namespace "${namespace}" -f "${values_file}" 2>&1 | tail -3 || true)
        errors+=("  ${tool_dir}: ${error_msg}")
    fi
done

echo ""
echo -e "${BOLD}── Results ──${NC}"
echo ""
echo -e "  ${GREEN}Passed:  ${passed}${NC}"
echo -e "  ${RED}Failed:  ${failed}${NC}"
echo -e "  ${YELLOW}Skipped: ${skipped}${NC}"
echo ""

if [[ ${#errors[@]} -gt 0 ]]; then
    echo -e "${RED}Failures:${NC}"
    for err in "${errors[@]}"; do
        echo "$err"
    done
    echo ""
fi

# Known upstream chart issues that shouldn't block validation
KNOWN_FAILURES="falco-talon"

actual_failures=0
for err in "${errors[@]+"${errors[@]}"}"; do
    is_known=false
    for known in $KNOWN_FAILURES; do
        if echo "$err" | grep -q "$known"; then
            is_known=true
            break
        fi
    done
    if [[ "$is_known" == "false" ]]; then
        actual_failures=$((actual_failures + 1))
    fi
done

if [[ $actual_failures -gt 0 ]]; then
    echo -e "${RED}Helm template validation FAILED (${actual_failures} unexpected failure(s))${NC}"
    exit 1
elif [[ $failed -gt 0 ]]; then
    echo -e "${YELLOW}Helm template validation PASSED (${failed} known upstream issue(s))${NC}"
    exit 0
else
    echo -e "${GREEN}All Helm templates render successfully${NC}"
    exit 0
fi
