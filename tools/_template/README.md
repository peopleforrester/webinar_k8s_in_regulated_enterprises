# [Tool Name]

> **CNCF Status:** [Graduated/Incubating/Sandbox/Non-CNCF]
> **Category:** [e.g., Policy Engine, Runtime Security, etc.]
> **Difficulty:** [Beginner/Intermediate/Advanced]
> **AKS Compatibility:** [Native/Supported/Manual]

## What It Does

[2-3 sentence explanation of what this tool does and why you'd use it in a Kubernetes environment.]

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | [specific controls] |
| SOC 2 | [specific controls] |
| DORA | [specific controls] |
| PCI-DSS | [specific controls] |

## Architecture

[Describe how this tool fits into the cluster — DaemonSet, Deployment, Operator, etc. Include a text diagram if helpful.]

## Quick Start (AKS)

### Prerequisites
- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured

### Install

[Helm install command with -f values.yaml]

### Verify

[kubectl commands to verify the installation is healthy]

## Key Configuration Decisions

[Explain the most important values.yaml settings and why they're set the way they are. Link to the values.yaml in this directory.]

## EKS / GKE Notes

[Brief notes on what would differ if running on EKS or GKE instead of AKS.]

## Certification Relevance

[Which CNCF certifications (CKA, CKAD, CKS, KCNA, KCSA) cover this tool and in what context.]

## Learn More

- [Official docs](link)
- [CNCF project page](link)
- [GitHub repository](link)
