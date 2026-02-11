# FinOps Cost Optimization Scenario

> **Tools:** Karpenter + Prometheus + Grafana
> **Category:** Cross-Tool Scenario
> **Difficulty:** Intermediate
> **Goal:** Demonstrate intelligent node autoscaling, workload right-sizing, and cost visibility using Karpenter with Prometheus metrics and Grafana dashboards.

## Quick Start (Automated Scripts)

Run the full demo with interactive pauses:

```bash
./scenarios/finops/run-demo.sh
```

Or run individual steps:

| Script | Description |
|--------|-------------|
| `01-baseline-costs.sh` | Queries Prometheus for current resource utilization and waste |
| `02-karpenter-consolidation.sh` | Demonstrates Karpenter node consolidation and right-sizing |
| `03-spot-workloads.sh` | Deploys workloads to Karpenter spot NodePool for cost savings |
| `run-demo.sh` | Orchestrates all three steps with narration pauses |

**Prerequisites:** AKS cluster with `install-tools.sh --tier=2,4` (Prometheus + Karpenter required).

## Overview

FinOps for Kubernetes means **knowing what you spend, why you spend it, and how to spend less without sacrificing reliability.** This scenario demonstrates three cost optimization techniques:

1. **Resource Utilization Baseline** — Query Prometheus to understand current resource requests vs. actual usage. Identify over-provisioned workloads that waste money.

2. **Karpenter Node Consolidation** — Watch Karpenter right-size nodes by selecting optimal VM SKUs for actual workload requirements instead of fixed-size VMSS node pools.

3. **Spot Instance Workloads** — Deploy fault-tolerant workloads to Karpenter spot NodePools for up to 90% cost savings on interruptible workloads.

## Architecture

```
┌─────────────────────────────────────────────────┐
│ Prometheus Stack (kube-prometheus-stack)         │
│                                                  │
│  Collects: node CPU/memory, pod requests/limits  │
│  Calculates: utilization ratios, waste metrics   │
│  Alerts: over-provisioned namespaces             │
└──────────┬──────────────────────────────────────┘
           │ metrics
           ▼
┌─────────────────────────┐    ┌──────────────────┐
│ Grafana Dashboard       │    │ Karpenter        │
│                          │    │                  │
│ - Cost per namespace     │    │ - Right-sizes    │
│ - Request vs actual      │    │   VM SKUs        │
│ - Waste identification   │    │ - Consolidates   │
│ - Spot vs on-demand      │    │   underutilized  │
└─────────────────────────┘    │   nodes          │
                                │ - Manages spot   │
                                │   instances      │
                                └──────────────────┘
```

## Regulatory Value

| Requirement | How This Scenario Satisfies It |
|-------------|-------------------------------|
| **DORA Article 11** — ICT capacity management | Karpenter optimizes node selection based on actual workload needs |
| **NCUA** — Fiduciary responsibility | Demonstrates cost efficiency in cloud infrastructure spending |
| **OSFI B-13** — Technology risk management | Resource monitoring prevents over/under-provisioning |
| **SOC 2 A1.1** — Capacity planning | Prometheus metrics provide evidence of capacity management |

## Learn More

- [Karpenter Documentation](https://karpenter.sh/)
- [AKS Node Auto Provisioning](https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning)
- [FinOps Foundation](https://www.finops.org/)
- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
