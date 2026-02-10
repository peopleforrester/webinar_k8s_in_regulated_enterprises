# Harbor

> **CNCF Status:** Graduated
> **Category:** Container Registry
> **Difficulty:** Advanced
> **AKS Compatibility:** Supported (alternative/complement to ACR)

## What It Does

Harbor is an enterprise-grade container registry that stores, signs, and scans container images. It provides vulnerability scanning (via integrated Trivy), role-based access control, image replication across registries, content trust (Cosign/Notary), project-level quota management, and detailed audit logging. In regulated Kubernetes environments, Harbor serves as a policy-enforced gateway ensuring only approved, scanned images reach production clusters.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Supply chain risk management (Part 748, Appendix A); access controls for software artifacts; audit trail for image distribution |
| SOC 2 | CC6.1 - Logical and physical access controls for registry; CC8.1 - Change management for container images |
| DORA | Article 9 - Access control and identity management for registry operations; Article 28 - ICT supply chain risk management |
| PCI-DSS | Req 6.3 - Secure software development (image provenance); Req 6.5 - Vulnerability scanning before deployment |

## Architecture

Harbor runs as a set of **Deployments** and **StatefulSets** in a dedicated namespace. The core components work together to provide a complete registry solution:

```
                                   +-------------------+
                                   |    Harbor Portal   |
                                   |    (Web UI)        |
                                   +--------+----------+
                                            |
                              +-------------+-------------+
                              |                           |
                    +---------v---------+     +-----------v----------+
                    |    Harbor Core     |     |    Harbor Jobservice  |
                    |  (API + Auth)      |     |  (Async Tasks:        |
                    +--------+----------+     |   replication, GC,    |
                             |                |   scan triggers)      |
               +-------------+----------+     +-----------+----------+
               |             |          |                 |
     +---------v---+  +-----v-----+  +-v---------+  +---v---------+
     |  Registry    |  | Database  |  |   Redis    |  | Trivy       |
     |  (OCI Store) |  | (Postgres)|  | (Cache +   |  | (Vuln       |
     |              |  |           |  |  Job Queue)|  |  Scanner)   |
     +--------------+  +-----------+  +-----------+  +-------------+
```

**Component responsibilities:**

- **Core**: Central API server handling authentication, authorization, project management, and webhook notifications.
- **Portal**: Web UI for managing projects, users, robot accounts, and viewing scan results.
- **Registry**: OCI-compliant image storage backend (stores layers and manifests).
- **Jobservice**: Asynchronous job executor for replication, garbage collection, and scan orchestration.
- **Database (PostgreSQL)**: Stores metadata -- projects, users, scan results, audit logs, replication rules.
- **Redis**: Session cache, job queue broker, and rate limiting.
- **Trivy**: Integrated vulnerability scanner that runs on every image push (when configured).

## Quick Start (AKS)

### Prerequisites
- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured
- A DNS name or IP for Harbor ingress (or use port-forward for lab testing)
- Storage class available for PersistentVolumeClaims (AKS default `managed-csi` works)

### Install

```bash
helm repo add harbor https://helm.goharbor.io
helm repo update

helm install harbor harbor/harbor \
  --namespace harbor-system \
  --create-namespace \
  -f values.yaml
```

### Verify

```bash
# Check all pods are running (may take 2-3 minutes for database init)
kubectl get pods -n harbor-system

# Expected pods (all should be Running or Completed):
#   harbor-core-*
#   harbor-database-*
#   harbor-jobservice-*
#   harbor-portal-*
#   harbor-redis-*
#   harbor-registry-*
#   harbor-trivy-*

# Check Harbor is responding (port-forward for lab access)
kubectl port-forward -n harbor-system svc/harbor-core 8443:443 &
curl -k https://localhost:8443/api/v2.0/health

# Log in to Harbor UI
# Default credentials: admin / Harbor12345 (change immediately)
# URL: https://localhost:8443 (or your ingress URL)

# Test image push (after creating a project in the UI)
docker login harbor.example.com -u admin
docker tag nginx:latest harbor.example.com/regulated-apps/nginx:latest
docker push harbor.example.com/regulated-apps/nginx:latest

# Check scan results after push
curl -k -u admin:Harbor12345 \
  https://harbor.example.com/api/v2.0/projects/regulated-apps/repositories/nginx/artifacts?with_scan_overview=true
```

## Key Configuration Decisions

See [values.yaml](./values.yaml) for the full configuration.

- **Trivy as default scanner**: Harbor integrates Trivy directly, providing automatic vulnerability scanning on every image push. This eliminates the gap between image upload and security assessment.
- **Auto-scan on push**: Every image pushed to Harbor is immediately queued for scanning. No manual intervention required, ensuring no unscanned image enters the registry.
- **Internal PostgreSQL for lab**: The bundled PostgreSQL is suitable for demos and small deployments. Production deployments should use Azure Database for PostgreSQL Flexible Server for HA, automated backups, and geo-replication.
- **Notary disabled, Cosign preferred**: Notary (Docker Content Trust) is being superseded by Cosign (Sigstore) for image signing. Cosign is simpler, supports keyless signing, and integrates with Kyverno for admission-time verification.
- **Azure Disk persistence**: All stateful components use PVCs backed by Azure Managed Disks (`managed-csi` StorageClass), providing snapshot-capable, encrypted-at-rest storage.
- **Robot accounts for CI/CD**: Robot accounts provide scoped, revocable credentials for automated pipelines instead of sharing human user accounts.
- **Metrics enabled**: Prometheus metrics are exposed on all components for monitoring registry health, scan throughput, and storage utilization.

## EKS / GKE Notes

- **EKS**: Replace Azure Disk StorageClass with `gp3` (EBS). If using ALB Ingress Controller, update `expose.type` and ingress annotations. ECR and Harbor can coexist -- use Harbor for policy enforcement and ECR as a pull-through cache.
- **GKE**: Replace Azure Disk StorageClass with `standard-rwo` (Persistent Disk). GKE ingress annotations differ from nginx ingress. Artifact Registry is the GKE-native equivalent; Harbor adds multi-cloud portability and richer policy controls.
- **Storage backends**: All three clouds support S3-compatible or blob storage backends for the registry layer. For large-scale deployments, switch from PVC-backed storage to Azure Blob, S3, or GCS for the registry data.

## Certification Relevance

- **CKS (Certified Kubernetes Security Specialist)**: Supply chain security domain covers private registries, image scanning, image signing, and admission control based on registry policies. Harbor demonstrates all of these capabilities.
- **KCSA (Kubernetes and Cloud Native Security Associate)**: Image scanning, registry security, and access control for container artifacts are key exam topics. Harbor provides a concrete implementation of these concepts.

## Learn More

- [Official docs](https://goharbor.io/docs/)
- [CNCF project page](https://www.cncf.io/projects/harbor/)
- [GitHub repository](https://github.com/goharbor/harbor)
- [Harbor Helm chart](https://github.com/goharbor/harbor-helm)
- [Cosign + Harbor integration](https://goharbor.io/docs/main/working-with-projects/project-configuration/cosign-verification/)
