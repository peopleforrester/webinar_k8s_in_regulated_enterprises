# Falco Talon

> **CNCF Status:** Community (Falcosecurity)
> **Category:** Automated Response
> **Difficulty:** Intermediate
> **AKS Compatibility:** Supported

## What It Does

Falco Talon is an automated threat response engine for Kubernetes. It receives Falco alerts and takes immediate action: isolating compromised pods with network policies, labeling suspicious workloads for forensic investigation, or terminating containers exhibiting malicious behavior. This transforms security from "detect and alert" to "detect and contain," reducing dwell time between threat detection and response.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Part 748 - Automated incident response procedures, documented and executable response actions |
| DORA | Art 10 - Automated detection and response capabilities for ICT-related incidents |
| DORA | Art 11 - ICT-related incident management process with documented response procedures |

## Architecture

Falco Talon runs as a Deployment in the `falco` namespace. It receives events from Falcosidekick (or directly from Falco via gRPC) and executes response rules against the Kubernetes API. A dedicated ServiceAccount with scoped RBAC permissions allows Talon to manage pods and network policies.

```
+--------+   gRPC/HTTP   +---------------+   webhook   +--------+
| Falco  | ------------> | Falcosidekick | ----------> | Talon  |
+--------+               +---------------+             +---+----+
                                                           |
                                            Kubernetes API |
                                                           v
                                                    +--------------+
                                                    | Actions:     |
                                                    | - NetworkPol |
                                                    | - Label      |
                                                    | - Terminate  |
                                                    | - Script     |
                                                    +--------------+
```

## Quick Start (AKS)

### Prerequisites
- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured
- Falco and Falcosidekick already installed

### Install

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco-talon falcosecurity/falco-talon \
  --namespace falco \
  -f values.yaml
```

### Verify

```bash
# Check pod status
kubectl get pods -n falco -l app.kubernetes.io/name=falco-talon

# Verify RBAC permissions are in place
kubectl get clusterrole falco-talon -o yaml

# Check logs for successful Falco connection
kubectl logs -n falco -l app.kubernetes.io/name=falco-talon --tail=20
```

## Key Configuration Decisions

See [`values.yaml`](./values.yaml) for the full Helm configuration and [`response-rules.yaml`](./response-rules.yaml) for the automated response rules.

- **Default action set to `log`** (`config.defaultAction: log`) -- unmatched events are logged but never acted on. Automated actions only fire for explicitly configured threat patterns.
- **Watch rules enabled** (`config.watchRules: true`) -- Talon reloads rules from its ConfigMap without requiring a pod restart, enabling dynamic updates via GitOps.
- **Response rules** (in `response-rules.yaml`) define five threat scenarios:
  - **Crypto mining** -- network isolation via deny-all NetworkPolicy
  - **Privilege escalation** -- immediate pod termination (gracePeriod: 0)
  - **Shell/exec access** -- label pods as suspicious for investigation
  - **Credential access** -- label pods requiring investigation
  - **Data exfiltration** -- block egress traffic for pods in sensitive namespaces
- **Security context** -- runs as non-root (UID 1000) with a read-only root filesystem, following least-privilege principles.
- **Scoped RBAC** -- permissions limited to pods (get/list/delete/patch), pods/exec (create), and network policies (get/list/create/patch). No delete permission on network policies to prevent removing existing restrictions.
- **ServiceMonitor enabled** -- exposes metrics for tracking events received, actions executed, and action failures.

## EKS / GKE Notes

No significant differences. Falco Talon is a standard Kubernetes Deployment that works identically across AKS, EKS, and GKE. The RBAC rules and response actions use core Kubernetes APIs with no cloud-specific dependencies.

## Certification Relevance

- **CKS** (Certified Kubernetes Security Specialist) -- runtime security, automated incident response, network policy enforcement, and RBAC design for security tooling.

## Learn More

- [Official documentation](https://docs.falco-talon.org/)
- [GitHub repository](https://github.com/falcosecurity/falco-talon)
- [Falcosecurity organization](https://github.com/falcosecurity)
- [Response action reference](https://docs.falco-talon.org/docs/actionners/list/)
