#!/usr/bin/env bash
# Install all security tools via Helm
# Installs: Falco, Falcosidekick, Kyverno, Trivy Operator, Kubescape

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECURITY_TOOLS_DIR="${SCRIPT_DIR}/../security-tools"
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
TOTAL_STEPS=6
CURRENT_STEP=0

progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local PCT=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo -e "${YELLOW}[${CURRENT_STEP}/${TOTAL_STEPS}] (${PCT}%) $1${NC}"
}

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Installing Security Tools${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# Check prerequisites
command -v helm >/dev/null 2>&1 || { echo -e "${RED}helm not found${NC}"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl not found${NC}"; exit 1; }

# Verify cluster connection
kubectl cluster-info >/dev/null 2>&1 || { echo -e "${RED}Cannot connect to cluster${NC}"; exit 1; }

# Add Helm repos
progress "Adding Helm repositories..."
helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
helm repo add aqua https://aquasecurity.github.io/helm-charts/ 2>/dev/null || true
helm repo add kubescape https://kubescape.github.io/helm-charts/ 2>/dev/null || true
helm repo update
echo -e "${GREEN}  Helm repos configured${NC}"
echo ""

# Install Falco
progress "Installing Falco (runtime threat detection)..."
helm upgrade --install falco falcosecurity/falco \
    --namespace falco \
    --create-namespace \
    -f "${SECURITY_TOOLS_DIR}/falco/values.yaml" \
    --wait --timeout 5m
echo -e "${GREEN}  Falco installed${NC}"
echo ""

# Install Falcosidekick
progress "Installing Falcosidekick (alert forwarding)..."
helm upgrade --install falcosidekick falcosecurity/falcosidekick \
    --namespace falco \
    -f "${SECURITY_TOOLS_DIR}/falcosidekick/values.yaml" \
    --wait --timeout 3m
echo -e "${GREEN}  Falcosidekick installed${NC}"
echo ""

# Install Kyverno
progress "Installing Kyverno (policy engine)..."
helm upgrade --install kyverno kyverno/kyverno \
    --namespace kyverno \
    --create-namespace \
    -f "${SECURITY_TOOLS_DIR}/kyverno/values.yaml" \
    --wait --timeout 5m
echo -e "${GREEN}  Kyverno installed${NC}"
echo ""

# Install Trivy Operator
progress "Installing Trivy Operator (vulnerability scanning)..."
helm upgrade --install trivy-operator aqua/trivy-operator \
    --namespace trivy-system \
    --create-namespace \
    -f "${SECURITY_TOOLS_DIR}/trivy/values.yaml" \
    --wait --timeout 5m
echo -e "${GREEN}  Trivy Operator installed${NC}"
echo ""

# Install Kubescape
progress "Installing Kubescape (compliance scanning)..."
helm upgrade --install kubescape kubescape/kubescape-operator \
    --namespace kubescape \
    --create-namespace \
    -f "${SECURITY_TOOLS_DIR}/kubescape/values.yaml" \
    --wait --timeout 5m
echo -e "${GREEN}  Kubescape installed${NC}"
echo ""

echo -e "${BOLD}========================================${NC}"
echo -e "${GREEN}  All security tools installed (100%)${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "Verifying installations:"
echo ""
for NS in falco kyverno trivy-system kubescape; do
    PODS=$(kubectl get pods -n "${NS}" --no-headers 2>/dev/null | wc -l)
    READY=$(kubectl get pods -n "${NS}" --no-headers 2>/dev/null | grep -c "Running" || true)
    echo "  ${NS}: ${READY}/${PODS} pods running"
done
echo ""
echo "Next step: Deploy demo workloads or run the demo"
echo "  ./run-demo.sh"
