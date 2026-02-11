# ABOUTME: Build automation for the AKS Regulated Enterprise reference architecture.
# ABOUTME: Provides targets for testing, validation, installation, and cleanup.

.PHONY: help test test-unit test-integration test-e2e lint validate install clean

# Default target
help: ## Show this help
	@echo "AKS Regulated Enterprise — Make Targets"
	@echo ""
	@echo "Testing:"
	@echo "  make test              Run unit tests (no cluster needed)"
	@echo "  make test-unit         Run unit tests only"
	@echo "  make test-integration  Run integration tests (needs cluster)"
	@echo "  make test-e2e          Run e2e tests (needs cluster + tools)"
	@echo "  make test-all          Run all test suites"
	@echo ""
	@echo "Validation:"
	@echo "  make lint              Run YAML + shell + Terraform validation"
	@echo "  make validate          Alias for lint"
	@echo ""
	@echo "Cluster Operations:"
	@echo "  make install           Install all tools (tier 1-4)"
	@echo "  make install-tier1     Install security tools only"
	@echo "  make install-tier2     Install observability tools"
	@echo "  make install-tier3     Install platform tools"
	@echo "  make install-tier4     Enable Karpenter"
	@echo "  make clean             Remove all installed tools"
	@echo ""
	@echo "Scenarios:"
	@echo "  make demo-attack       Run attack-detect-prevent demo"
	@echo "  make demo-gitops       Run GitOps delivery demo"
	@echo "  make demo-zerotrust    Run zero-trust networking demo"
	@echo "  make demo-finops       Run FinOps cost optimization demo"

# ============================================================================
# TESTING
# ============================================================================

test: test-unit ## Run unit tests (default)

test-unit: ## Run unit tests (no cluster needed)
	@./tests/run-all.sh --unit

test-integration: ## Run integration tests (needs running cluster)
	@./tests/run-all.sh --integration

test-e2e: ## Run e2e tests (needs cluster with tools installed)
	@./tests/run-all.sh --e2e

test-all: ## Run all test suites
	@./tests/run-all.sh --all

# ============================================================================
# VALIDATION / LINTING
# ============================================================================

lint: ## Run YAML, shell, and Terraform validation
	@echo "Running YAML syntax check..."
	@./tests/unit/test-yaml-syntax.sh
	@echo ""
	@echo "Running shell syntax check..."
	@./tests/unit/test-shell-syntax.sh
	@echo ""
	@echo "Running Terraform validation..."
	@./tests/unit/test-terraform-validate.sh

validate: lint ## Alias for lint

# ============================================================================
# CLUSTER OPERATIONS
# ============================================================================

install: ## Install all tools (tier 1-4)
	@./scripts/install-tools.sh

install-tier1: ## Install Tier 1 security tools
	@./scripts/install-tools.sh --tier=1

install-tier2: ## Install Tier 2 observability tools
	@./scripts/install-tools.sh --tier=2

install-tier3: ## Install Tier 3 platform tools
	@./scripts/install-tools.sh --tier=3

install-tier4: ## Enable Tier 4 AKS-managed (Karpenter)
	@./scripts/install-tools.sh --tier=4

clean: ## Remove all installed tools
	@./scripts/cleanup.sh --full

# ============================================================================
# SCENARIOS
# ============================================================================

demo-attack: ## Run attack-detect-prevent scenario
	@./scenarios/attack-detect-prevent/run-demo.sh

demo-gitops: ## Run GitOps delivery scenario
	@./scenarios/gitops-delivery/run-demo.sh

demo-zerotrust: ## Run zero-trust networking scenario
	@./scenarios/zero-trust/run-demo.sh

demo-finops: ## Run FinOps cost optimization scenario
	@./scenarios/finops/run-demo.sh
