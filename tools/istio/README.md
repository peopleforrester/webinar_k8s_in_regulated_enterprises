# Istio

> **CNCF Status:** Graduated
> **Category:** Service Mesh
> **Difficulty:** Advanced
> **AKS Compatibility:** Supported

## What It Does

Istio is a service mesh that provides mutual TLS (mTLS), traffic management, observability,
and fine-grained authorization between services in a Kubernetes cluster. It deploys Envoy
proxy sidecars alongside every application pod, intercepting all inbound and outbound
network traffic. This transparent interception layer enables encryption, access control,
telemetry collection, and traffic shaping without requiring application code changes.

For regulated financial environments, Istio solves a fundamental problem: proving that
all service-to-service communication is encrypted and authorized, with a complete audit
trail of every network interaction.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Encryption in transit for all inter-service communication, network segmentation through authorization policies, continuous monitoring of service interactions |
| SOC 2 | CC6.1 Logical access controls -- AuthorizationPolicy enforces service-to-service identity; CC6.6 Network security -- mTLS encrypts all pod traffic with automatic certificate rotation |
| DORA | Article 9 Data protection -- mTLS ensures data confidentiality in transit; Article 10 Anomaly detection -- access logs and distributed tracing surface abnormal traffic patterns |
| PCI-DSS | Requirement 4.1 Encryption in transit -- STRICT mTLS between all services; Requirement 7 Access control -- AuthorizationPolicy implements least-privilege service communication |

## Architecture

Istio consists of a control plane (istiod) and a data plane (Envoy sidecar proxies):

```
                        +---------------------------+
                        |        istiod             |
                        |  (Control Plane)          |
                        |                           |
                        |  +-----+  +------+  +---+ |
                        |  | CA  |  | Pilot|  |Cfg| |
                        |  +--+--+  +--+---+  +-+-+ |
                        +-----|--------|---------|---+
                              |        |         |
                    Issues    | Pushes | Pushes  |
                    certs     | routes | policies|
                              |        |         |
          +-------------------+--------+---------+----------+
          |                   |        |         |          |
    +-----v------+    +------v-----+  |   +-----v------+  |
    | Pod A       |    | Pod B      |  |   | Pod C      |  |
    | +--------+  |    | +--------+ |  |   | +--------+ |  |
    | |  App   |  |    | |  App   | |  |   | |  App   | |  |
    | +---+----+  |    | +---+----+ |  |   | +---+----+ |  |
    |     |       |    |     |      |  |   |     |      |  |
    | +---v----+  |    | +---v----+ |  |   | +---v----+ |  |
    | | Envoy  +--+----+-> Envoy  | |  |   | | Envoy  | |  |
    | | Sidecar|  |mTLS| | Sidecar| |  |   | | Sidecar| |  |
    | +--------+  |    | +--------+ |  |   | +--------+ |  |
    +-----------  +    +------------+  |   +------------+  |
                                       |                   |
                              +--------v-------------------v--+
                              |       Istio Gateway           |
                              |       (Ingress/Egress)        |
                              |       +------------------+    |
                              |       | Envoy Proxy      |    |
                              |       +------------------+    |
                              +-------------------------------+
                                          |
                                    External Traffic
```

**How mTLS Works Between Pods:**

1. istiod acts as a Certificate Authority (CA), issuing SPIFFE-based X.509 certificates
   to every Envoy sidecar.
2. When Pod A sends a request to Pod B, the Envoy sidecars perform a TLS handshake
   using their certificates -- mutually authenticating both sides.
3. All traffic between pods is encrypted. The application code sees plain HTTP;
   Envoy handles encryption transparently.
4. Certificates rotate automatically (default 24 hours), limiting the blast radius
   of a compromised certificate.

**Key Components:**

- **istiod** -- The control plane. Manages certificates, distributes routing rules and
  security policies to all Envoy sidecars. Single binary combining Pilot, Citadel, and
  Galley functionality.
- **Envoy Sidecar** -- Injected into every labeled pod. Intercepts all TCP traffic on
  the pod's network namespace. Handles mTLS, load balancing, retries, and access logging.
- **Istio Gateway** -- Manages ingress and egress traffic at the mesh boundary.
  Replaces traditional Kubernetes Ingress with richer routing and security capabilities.

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured
- istioctl installed (optional but recommended for debugging)

### Install via Helm

```bash
# Add the Istio Helm repository
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

# Install the Istio base chart (CRDs and cluster-wide resources)
helm install istio-base istio/base \
  --namespace istio-system \
  --create-namespace

# Install istiod (the control plane)
helm install istiod istio/istiod \
  --namespace istio-system \
  -f values.yaml

# Verify the control plane is running
kubectl get pods -n istio-system
```

### Enable Sidecar Injection

```bash
# Label the namespace to enable automatic sidecar injection
kubectl label namespace compliant-app istio-injection=enabled

# Restart existing pods to pick up the sidecar
kubectl rollout restart deployment -n compliant-app
```

### Apply Security Policies

```bash
# Enforce STRICT mTLS mesh-wide
kubectl apply -f manifests/peer-authentication.yaml

# Apply zero-trust authorization policies
kubectl apply -f manifests/authorization-policy.yaml

# Configure ingress gateway routing
kubectl apply -f manifests/gateway.yaml

# Apply destination rules with circuit breakers
kubectl apply -f manifests/destination-rule.yaml
```

### Verify

```bash
# Confirm istiod is healthy
kubectl get pods -n istio-system

# Confirm sidecars are injected (2/2 containers per pod)
kubectl get pods -n compliant-app

# Check mTLS status between services
istioctl x describe pod <pod-name> -n compliant-app

# Verify PeerAuthentication is enforced
kubectl get peerauthentication -A

# View AuthorizationPolicy rules
kubectl get authorizationpolicy -A
```

## Key Configuration Decisions

Configuration is in [`values.yaml`](./values.yaml). Key decisions:

- **mTLS mode: STRICT** -- All inter-service communication must be encrypted. PERMISSIVE
  mode (accepts both plain and mTLS) is useful during migration but should never be used
  in regulated production. STRICT mode ensures no unencrypted traffic is possible.

- **Sidecar injection: namespace label vs pod annotation** -- Namespace-level labeling
  (`istio-injection=enabled`) is the recommended approach. It ensures every pod in the
  namespace gets a sidecar without relying on developers to add annotations. Pod-level
  annotation (`sidecar.istio.io/inject: "true"`) provides fine-grained control when only
  specific pods need the mesh.

- **Gateway API vs Istio Gateway** -- Istio supports both the Kubernetes Gateway API
  (the standard) and its own Gateway CRD. For greenfield deployments, prefer the
  Kubernetes Gateway API for portability. This repo uses the Istio Gateway CRD for
  broader compatibility with existing clusters.

- **Ambient mesh vs sidecar mode** -- Ambient mesh (GA in Istio 1.24) uses node-level
  ztunnel proxies instead of per-pod sidecars, reducing resource overhead by approximately
  50%. However, sidecar mode provides stronger isolation (per-pod proxy) and is better
  understood by auditors. Use sidecar mode for regulated environments until ambient mesh
  matures in compliance tooling.

- **Resource overhead** -- Each Envoy sidecar consumes approximately 50-100Mi memory and
  10-50m CPU. For a namespace with 20 pods, budget an additional 1-2Gi memory and 200m-1000m
  CPU for sidecars. The values.yaml configures conservative defaults suitable for demo and
  lab environments.

- **Access logging** -- Enabled for all mesh traffic. Access logs provide an audit trail
  of every request (source, destination, response code, latency). Essential for regulatory
  compliance but generates significant log volume in production. Configure log rotation
  and retention policies accordingly.

- **Tracing sample rate** -- Set to 100% for lab environments to capture every request
  in distributed traces. In production, reduce to 1% to manage overhead while still
  capturing representative samples for anomaly detection.

## EKS / GKE Notes

Istio works on any conformant Kubernetes distribution. Cloud-specific considerations:

- **GKE** -- Google offers Anthos Service Mesh (ASM), a managed Istio distribution with
  Google support and automatic upgrades. ASM is the recommended path for GKE clusters in
  regulated environments, as Google manages the control plane lifecycle.

- **EKS** -- AWS offers App Mesh as their native service mesh, but it uses a different
  API surface. Istio installs directly on EKS without modification. The Helm chart and
  all manifests in this directory work as-is on EKS.

- **AKS** -- Azure offers an Istio-based service mesh add-on (preview/GA depending on
  region). The add-on manages istiod lifecycle through the AKS control plane. For
  maximum control and configuration flexibility, the standalone Helm install shown above
  is recommended. The add-on is suitable when you prefer Azure-managed upgrades.

## Certification Relevance

| Certification | Relevance |
|--------------|-----------|
| **CKS** (Certified Kubernetes Security Specialist) | Network security -- mTLS, service mesh concepts, network segmentation, encryption in transit |
| **KCSA** (Kubernetes and Cloud Native Security Associate) | Understanding network policies, mTLS fundamentals, zero-trust networking, service identity |

## Learn More

- [Istio Documentation](https://istio.io/latest/docs/)
- [CNCF Project Page](https://www.cncf.io/projects/istio/)
- [GitHub Repository](https://github.com/istio/istio)
- [Istio by Example](https://istiobyexample.dev/) -- practical usage patterns
- [Envoy Proxy Documentation](https://www.envoyproxy.io/docs/) -- understand the data plane
- [SPIFFE/SPIRE](https://spiffe.io/) -- the identity framework behind Istio certificates
