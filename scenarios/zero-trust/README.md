# Zero-Trust Networking Scenario

> **Tools:** Istio + Kubernetes NetworkPolicy + Falco
> **Category:** Cross-Tool Scenario
> **Difficulty:** Advanced
> **Goal:** Enforce mutual TLS between all services, apply default-deny authorization policies, and demonstrate network-level isolation that meets regulatory zero-trust requirements.

## Quick Start (Automated Scripts)

Run the full demo with interactive pauses:

```bash
./scenarios/zero-trust/run-demo.sh
```

Or run individual steps:

| Script | Description |
|--------|-------------|
| `01-deploy-mesh.sh` | Labels namespace for sidecar injection, deploys multi-service app |
| `02-enforce-mtls.sh` | Applies PeerAuthentication for STRICT mTLS, verifies encryption |
| `03-authorization-policies.sh` | Applies default-deny + allow rules, tests permit/block |
| `04-network-policies.sh` | Applies Kubernetes NetworkPolicies for L3/L4 isolation |
| `run-demo.sh` | Orchestrates all four steps with narration pauses |

**Prerequisites:** AKS cluster with `install-tools.sh --tier=1,3` (Istio + Falco required).

## Overview

Zero-trust networking means **no implicit trust between any services**. Every connection must be authenticated, authorized, and encrypted — regardless of whether it originates inside or outside the cluster.

This scenario demonstrates four defense-in-depth layers:

1. **Mutual TLS (Istio PeerAuthentication)** — Every pod-to-pod connection encrypted with auto-rotated certificates. SPIFFE identity verification ensures only legitimate workloads communicate.

2. **Authorization Policies (Istio AuthorizationPolicy)** — Layer 7 access control based on service identity, HTTP methods, and paths. Default-deny with explicit allow rules.

3. **Network Policies (Kubernetes)** — Layer 3/4 segmentation. Controls which pods can communicate at the IP/port level, independent of Istio.

4. **Runtime Detection (Falco)** — Detects and alerts on unauthorized network activity that bypasses policy layers.

## Architecture

```
                     ┌─────────────────────────────────────────┐
                     │         Zero-Trust Layers                │
                     ├─────────────────────────────────────────┤
 L7 Identity     ──▸ │  Istio AuthorizationPolicy              │
                     │  SPIFFE identity + HTTP method/path      │
                     ├─────────────────────────────────────────┤
 mTLS Encryption ──▸ │  Istio PeerAuthentication (STRICT)      │
                     │  Auto-rotated certs, reject plaintext    │
                     ├─────────────────────────────────────────┤
 L3/L4 Isolation ──▸ │  Kubernetes NetworkPolicy               │
                     │  Pod-to-pod IP/port filtering            │
                     ├─────────────────────────────────────────┤
 Runtime Guard   ──▸ │  Falco                                  │
                     │  Detect policy bypass, anomalous traffic │
                     └─────────────────────────────────────────┘
```

## Multi-Service Application

The demo deploys three services to simulate a microservice architecture:

```
                    ┌──────────┐
 External traffic → │ frontend │ ← Only service exposed
                    └────┬─────┘
                         │ (allowed)
                    ┌────▼─────┐
                    │ backend  │ ← Accepts only from frontend
                    └────┬─────┘
                         │ (allowed)
                    ┌────▼──────┐
                    │ database  │ ← Accepts only from backend
                    └───────────┘
```

Policies enforce this service graph. Direct frontend→database or external→backend connections are **blocked**.

## Regulatory Value

| Requirement | How This Scenario Satisfies It |
|-------------|-------------------------------|
| **NCUA Part 748** — Encryption of member data in transit | Istio STRICT mTLS encrypts all pod-to-pod traffic |
| **DORA Article 9** — Network segmentation for ICT assets | AuthorizationPolicy + NetworkPolicy enforce microsegmentation |
| **PCI-DSS 4.1** — Encrypt cardholder data across networks | mTLS provides TLS 1.3 encryption for all internal traffic |
| **SOC 2 CC6.1** — Logical access controls | SPIFFE identity-based authorization (not IP-based) |
| **FFIEC** — Defense in depth | Four independent security layers (mTLS, AuthZ, NetPol, Runtime) |
| **NIST 800-207** — Zero Trust Architecture | Identity-verified, least-privilege, continuously monitored |

## Learn More

- [Istio Security Documentation](https://istio.io/latest/docs/concepts/security/)
- [NIST SP 800-207: Zero Trust Architecture](https://csrc.nist.gov/publications/detail/sp/800-207/final)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [SPIFFE (Secure Production Identity Framework)](https://spiffe.io/)
- [CNCF Zero Trust Whitepaper](https://www.cncf.io/blog/zero-trust-security/)
