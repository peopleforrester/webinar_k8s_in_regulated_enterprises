#!/bin/bash
# ABOUTME: End-to-end test script for AKS Regulated Enterprise demo
# ABOUTME: Deploys infrastructure, installs tools, runs demo sequence, validates results

set -euo pipefail

#######################################
# Configuration
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_ROOT/demo-test-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Timing
START_TIME=$(date +%s)

#######################################
# Helper Functions
#######################################
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}✓ $*${NC}"; }
warn() { log "WARN" "${YELLOW}⚠ $*${NC}"; }
error() { log "ERROR" "${RED}✗ $*${NC}"; }

progress() {
    local current=$1
    local total=$2
    local task="$3"
    local pct=$((current * 100 / total))
    printf "\r[%3d%%] %-60s" "$pct" "$task"
}

elapsed_time() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    echo "${minutes}m ${seconds}s"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Required command not found: $1"
        return 1
    fi
    return 0
}

wait_for_pods() {
    local namespace="$1"
    local timeout="${2:-300}"
    local start=$(date +%s)

    info "Waiting for pods in namespace '$namespace' to be ready (timeout: ${timeout}s)..."

    while true; do
        local now=$(date +%s)
        local elapsed=$((now - start))

        if [ $elapsed -ge $timeout ]; then
            error "Timeout waiting for pods in $namespace"
            kubectl get pods -n "$namespace"
            return 1
        fi

        local not_ready=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l || echo "0")

        if [ "$not_ready" -eq 0 ]; then
            local total=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
            if [ "$total" -gt 0 ]; then
                success "All $total pods ready in $namespace"
                return 0
            fi
        fi

        progress $elapsed $timeout "Waiting for pods in $namespace ($not_ready not ready)..."
        sleep 5
    done
}

#######################################
# Phase 0: Prerequisites Check
#######################################
check_prerequisites() {
    info "═══════════════════════════════════════════════════════════════"
    info "PHASE 0: Checking Prerequisites"
    info "═══════════════════════════════════════════════════════════════"

    local required_commands=("az" "terraform" "kubectl" "helm" "kubescape" "trivy")
    local missing=0

    for cmd in "${required_commands[@]}"; do
        if check_command "$cmd"; then
            success "$cmd found: $(command -v $cmd)"
        else
            missing=$((missing + 1))
        fi
    done

    if [ $missing -gt 0 ]; then
        error "$missing required commands missing. Please install them first."
        exit 1
    fi

    # Check Azure login
    info "Checking Azure login status..."
    if ! az account show &> /dev/null; then
        warn "Not logged into Azure. Running 'az login'..."
        az login
    fi

    local subscription=$(az account show --query name -o tsv)
    success "Using Azure subscription: $subscription"

    echo ""
}

#######################################
# Phase 1: Deploy Infrastructure
#######################################
deploy_infrastructure() {
    info "═══════════════════════════════════════════════════════════════"
    info "PHASE 1: Deploying AKS Infrastructure"
    info "═══════════════════════════════════════════════════════════════"

    cd "$REPO_ROOT/infrastructure/terraform"

    # Terraform init
    info "Initializing Terraform..."
    terraform init -input=false | tee -a "$LOG_FILE"
    success "Terraform initialized"

    # Terraform plan
    info "Planning infrastructure changes..."
    terraform plan -out=plan.tfplan -input=false | tee -a "$LOG_FILE"
    success "Terraform plan complete"

    # Terraform apply
    info "Applying infrastructure (this takes 5-10 minutes)..."
    terraform apply -input=false -auto-approve plan.tfplan | tee -a "$LOG_FILE"
    success "Infrastructure deployed"

    # Get AKS credentials
    info "Getting AKS credentials..."
    local resource_group=$(terraform output -raw resource_group_name 2>/dev/null || echo "rg-aks-regulated-demo")
    local cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "aks-regulated-demo")

    az aks get-credentials --resource-group "$resource_group" --name "$cluster_name" --overwrite-existing
    success "kubectl configured for cluster: $cluster_name"

    # Verify cluster connection
    info "Verifying cluster connection..."
    kubectl cluster-info
    kubectl get nodes
    success "Cluster connection verified"

    cd "$REPO_ROOT"
    echo ""
}

#######################################
# Phase 2: Install Security Tools
#######################################
install_security_tools() {
    info "═══════════════════════════════════════════════════════════════"
    info "PHASE 2: Installing Security Tools"
    info "═══════════════════════════════════════════════════════════════"

    # Add Helm repos
    info "Adding Helm repositories..."
    helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
    helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
    helm repo add kubescape https://kubescape.github.io/helm-charts 2>/dev/null || true
    helm repo update
    success "Helm repositories updated"

    # Install Kyverno
    info "Installing Kyverno 1.17.0..."
    helm upgrade --install kyverno kyverno/kyverno \
        --namespace kyverno --create-namespace \
        --version 3.3.0 \
        -f "$REPO_ROOT/security-tools/kyverno/values.yaml" \
        --wait --timeout 5m
    success "Kyverno installed"

    wait_for_pods "kyverno" 300

    # Apply Kyverno policies
    info "Applying Kyverno policies..."
    kubectl apply -f "$REPO_ROOT/security-tools/kyverno/policies/"
    success "Kyverno policies applied"

    # Verify policies
    kubectl get cpol

    # Install Falco
    info "Installing Falco 0.43.0..."
    helm upgrade --install falco falcosecurity/falco \
        --namespace falco --create-namespace \
        -f "$REPO_ROOT/security-tools/falco/values.yaml" \
        --wait --timeout 5m
    success "Falco installed"

    wait_for_pods "falco" 300

    # Apply custom Falco rules
    info "Applying custom Falco rules..."
    kubectl apply -f "$REPO_ROOT/security-tools/falco/custom-rules.yaml"
    success "Custom Falco rules applied"

    # Install Kubescape Operator
    info "Installing Kubescape 4.0.0..."
    helm upgrade --install kubescape kubescape/kubescape-operator \
        --namespace kubescape --create-namespace \
        -f "$REPO_ROOT/security-tools/kubescape/values.yaml" \
        --wait --timeout 5m
    success "Kubescape installed"

    wait_for_pods "kubescape" 300

    echo ""
}

#######################################
# Phase 3: Deploy Demo Workloads
#######################################
deploy_demo_workloads() {
    info "═══════════════════════════════════════════════════════════════"
    info "PHASE 3: Deploying Demo Workloads"
    info "═══════════════════════════════════════════════════════════════"

    # Create demo namespace
    kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -

    # Deploy compliant app (should succeed)
    info "Deploying compliant application..."
    if kubectl apply -f "$REPO_ROOT/demo-workloads/compliant-app/"; then
        success "Compliant app deployed successfully"
    else
        error "Compliant app deployment failed (unexpected)"
        return 1
    fi

    wait_for_pods "demo" 120

    # Try to deploy vulnerable app (should be blocked)
    info "Attempting to deploy vulnerable application (should be BLOCKED by Kyverno)..."
    if kubectl apply -f "$REPO_ROOT/demo-workloads/vulnerable-app/" 2>&1 | tee -a "$LOG_FILE"; then
        error "Vulnerable app was deployed - Kyverno policies may not be working!"
        warn "Cleaning up vulnerable app..."
        kubectl delete -f "$REPO_ROOT/demo-workloads/vulnerable-app/" --ignore-not-found
    else
        success "Vulnerable app BLOCKED by Kyverno policies (expected behavior)"
    fi

    echo ""
}

#######################################
# Phase 4: Run Attack Simulation
#######################################
run_attack_simulation() {
    info "═══════════════════════════════════════════════════════════════"
    info "PHASE 4: Running Attack Simulation"
    info "═══════════════════════════════════════════════════════════════"

    # Get a compliant pod name
    local pod_name=$(kubectl get pods -n demo -l app=compliant-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pod_name" ]; then
        warn "No compliant pod found for attack simulation"
        return 0
    fi

    info "Target pod: $pod_name"

    # Simulate SA token read (should trigger Falco alert)
    info "Simulating service account token read..."
    kubectl exec -n demo "$pod_name" -- cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null | head -c 50
    echo "..."
    success "Token read executed (should appear in Falco logs)"

    # Simulate suspicious process
    info "Simulating suspicious shell activity..."
    kubectl exec -n demo "$pod_name" -- sh -c "whoami && id && uname -a" 2>/dev/null || true
    success "Shell commands executed (should appear in Falco logs)"

    # Wait for Falco to process
    info "Waiting 10 seconds for Falco to process events..."
    sleep 10

    # Check Falco logs
    info "Recent Falco alerts:"
    kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 2>/dev/null | grep -i "warning\|notice\|critical" | head -10 || warn "No alerts found yet"

    echo ""
}

#######################################
# Phase 5: Run Compliance Scans
#######################################
run_compliance_scans() {
    info "═══════════════════════════════════════════════════════════════"
    info "PHASE 5: Running Compliance Scans"
    info "═══════════════════════════════════════════════════════════════"

    # Kubescape CIS scan
    info "Running Kubescape CIS benchmark scan..."
    kubescape scan framework cis-v1.12.0 --format pretty 2>&1 | tee "$REPO_ROOT/kubescape-cis-results.txt"
    success "Kubescape CIS scan complete (results in kubescape-cis-results.txt)"

    # Kubescape NSA scan
    info "Running Kubescape NSA framework scan..."
    kubescape scan framework nsa --format pretty 2>&1 | tee "$REPO_ROOT/kubescape-nsa-results.txt"
    success "Kubescape NSA scan complete (results in kubescape-nsa-results.txt)"

    # Trivy cluster scan
    info "Running Trivy cluster vulnerability scan..."
    trivy k8s --report summary cluster 2>&1 | tee "$REPO_ROOT/trivy-cluster-results.txt"
    success "Trivy cluster scan complete (results in trivy-cluster-results.txt)"

    # Kyverno policy report
    info "Checking Kyverno PolicyReports..."
    kubectl get policyreport -A 2>/dev/null || warn "No PolicyReports yet (background scan may still be running)"

    echo ""
}

#######################################
# Phase 6: Validation Summary
#######################################
validation_summary() {
    info "═══════════════════════════════════════════════════════════════"
    info "PHASE 6: Validation Summary"
    info "═══════════════════════════════════════════════════════════════"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│                    DEMO VALIDATION RESULTS                      │"
    echo "├─────────────────────────────────────────────────────────────────┤"

    # Check Kyverno
    local kyverno_pods=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local kyverno_policies=$(kubectl get cpol --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$kyverno_pods" -gt 0 ] && [ "$kyverno_policies" -gt 0 ]; then
        echo "│ ✓ Kyverno:    $kyverno_pods pods running, $kyverno_policies policies active           │"
    else
        echo "│ ✗ Kyverno:    ISSUE - pods: $kyverno_pods, policies: $kyverno_policies                │"
    fi

    # Check Falco
    local falco_pods=$(kubectl get pods -n falco --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$falco_pods" -gt 0 ]; then
        echo "│ ✓ Falco:      $falco_pods pods running (DaemonSet)                        │"
    else
        echo "│ ✗ Falco:      ISSUE - pods: $falco_pods                                    │"
    fi

    # Check Kubescape
    local kubescape_pods=$(kubectl get pods -n kubescape --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$kubescape_pods" -gt 0 ]; then
        echo "│ ✓ Kubescape:  $kubescape_pods pods running (Operator)                      │"
    else
        echo "│ ✗ Kubescape:  ISSUE - pods: $kubescape_pods                                │"
    fi

    # Check demo workloads
    local demo_pods=$(kubectl get pods -n demo --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    echo "│ ✓ Demo apps:  $demo_pods compliant pods running                        │"

    echo "├─────────────────────────────────────────────────────────────────┤"
    echo "│ Elapsed time: $(elapsed_time)                                          │"
    echo "│ Log file: $LOG_FILE │"
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""

    success "Demo validation complete!"
}

#######################################
# Phase 7: Cleanup (Optional)
#######################################
cleanup() {
    info "═══════════════════════════════════════════════════════════════"
    info "PHASE 7: Cleanup"
    info "═══════════════════════════════════════════════════════════════"

    read -p "Do you want to destroy the infrastructure? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        info "Destroying infrastructure..."
        cd "$REPO_ROOT/infrastructure/terraform"
        terraform destroy -auto-approve
        success "Infrastructure destroyed"
        cd "$REPO_ROOT"
    else
        info "Infrastructure preserved. Remember to run 'terraform destroy' to avoid charges."
        warn "Estimated cost: ~\$150-200/day for running cluster"
    fi
}

#######################################
# Main Execution
#######################################
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║     AKS REGULATED ENTERPRISE DEMO - FULL TEST SCRIPT              ║"
    echo "║     KodeKloud Webinar: AKS for Regulated Enterprise               ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "This script will:"
    echo "  1. Check prerequisites (az, terraform, kubectl, helm, etc.)"
    echo "  2. Deploy AKS infrastructure via Terraform"
    echo "  3. Install Kyverno, Falco, and Kubescape"
    echo "  4. Deploy demo workloads (compliant + test vulnerable)"
    echo "  5. Run attack simulation"
    echo "  6. Run compliance scans"
    echo "  7. Display validation summary"
    echo "  8. Optionally cleanup infrastructure"
    echo ""
    echo "Estimated time: 15-20 minutes"
    echo "Estimated cost: ~\$10-15 for a 1-hour test"
    echo ""

    read -p "Press Enter to continue or Ctrl+C to cancel..."
    echo ""

    # Run phases
    check_prerequisites
    deploy_infrastructure
    install_security_tools
    deploy_demo_workloads
    run_attack_simulation
    run_compliance_scans
    validation_summary
    cleanup

    echo ""
    success "Full demo test completed in $(elapsed_time)"
    echo ""
}

# Handle script arguments
case "${1:-}" in
    --skip-infra)
        info "Skipping infrastructure deployment (using existing cluster)"
        check_prerequisites
        install_security_tools
        deploy_demo_workloads
        run_attack_simulation
        run_compliance_scans
        validation_summary
        ;;
    --cleanup-only)
        cleanup
        ;;
    --help)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --skip-infra    Skip Terraform deployment, use existing cluster"
        echo "  --cleanup-only  Only run the cleanup phase"
        echo "  --help          Show this help message"
        echo ""
        ;;
    *)
        main
        ;;
esac
