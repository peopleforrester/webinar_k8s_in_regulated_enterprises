# KubeHound

> **CNCF Status:** Community (Datadog)
> **Category:** Attack Path Analysis
> **Difficulty:** Advanced
> **AKS Compatibility:** Manual

## What It Does

KubeHound builds a graph database of Kubernetes cluster resources and maps attack paths that an
adversary could follow to escalate privileges -- from a compromised pod all the way to cluster-admin.
It uses MITRE ATT&CK technique mappings to classify each attack step, enabling security teams to
identify and prioritize the most dangerous lateral movement paths before attackers exploit them.

## Regulatory Relevance

| Framework | Controls Addressed |
|-----------|-------------------|
| NCUA/FFIEC | Threat modeling and risk assessment (Part 748) |
| SOC 2 | CC3.2 - Risk identification and assessment |
| DORA | Article 26 - Threat-led penetration testing (TLPT) |
| PCI-DSS | 11.4 - Penetration testing methodology |

## Architecture

KubeHound runs **outside the cluster** as a Docker Compose stack. It connects to the target
cluster via kubeconfig, collects resource state from the Kubernetes API, and builds an attack
graph in a graph database.

```
+------------------+                    +------------------+
| KubeHound        |  K8s API (read)    | AKS Cluster      |
| (Docker Compose) | -----------------> | (kubeconfig)     |
+--------+---------+                    +------------------+
         |
         | Builds attack graph
         v
+------------------+     Queries     +------------------+
| Graph Database   | <-------------- | Security Team    |
| (Neo4j)          |                 | (Cypher queries) |
+------------------+                 +------------------+
```

Components:
- **KubeHound engine**: Collects cluster state and builds the attack graph
- **Neo4j / JanusGraph**: Graph database storing nodes (resources) and edges (attack paths)
- **Query interface**: Gremlin console or Cypher queries for attack path analysis

**Note**: KubeHound requires kubeconfig access to the target cluster but does not deploy any
workloads into it. This makes it safe for production analysis without cluster modifications.

## Quick Start (AKS)

### Prerequisites
- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Docker and Docker Compose installed on your workstation
- kubectl configured with access to the target cluster

### Install

```bash
# Start KubeHound with graph database
docker compose up -d

# Ingest cluster data
docker compose exec kubehound kubehound

# Access the graph UI (Gremlin console)
# Open http://localhost:8182
```

### Verify

```bash
# Check containers are running
docker compose ps

# Verify cluster data was ingested
docker compose exec kubehound kubehound --dry-run

# Run a sample attack path query
docker compose exec kubehound \
  kubehound query --file /queries/attack-paths.cypher
```

## Key Configuration Decisions

See [docker-compose.yaml](./docker-compose.yaml) and the [queries/](./queries/) directory.

- **Runs outside the cluster**: KubeHound uses read-only Kubernetes API access via kubeconfig. No agents or DaemonSets are deployed into the cluster, making it non-invasive for production use.
- **Pre-built queries**: The `queries/` directory contains Cypher queries for common analysis scenarios:
  - `attack-paths.cypher` - General attack path discovery across all resource types
  - `privilege-escalation.cypher` - Paths from compromised pod to cluster-admin
  - `identity-attacks.cypher` - Identity and credential-based attack vectors
- **MITRE ATT&CK mapping**: Each attack path edge is annotated with MITRE ATT&CK technique IDs, enabling security teams to map findings to threat intelligence frameworks.
- **Graph database persistence**: Neo4j data is persisted via Docker volumes, allowing repeated queries without re-ingestion.

## EKS / GKE Notes

- **EKS**: Ensure kubeconfig uses `aws eks get-token` for authentication. IAM roles must have read access to the Kubernetes API. No other changes required.
- **GKE**: Ensure kubeconfig uses `gke-gcloud-auth-plugin` for authentication. Works with both Standard and Autopilot clusters since KubeHound only reads cluster state.
- **Multi-cluster**: Run separate ingestion passes per cluster, or use KubeHound as a Service (KHaaS) for centralized analysis across clusters.

## Certification Relevance

- **CKS (Certified Kubernetes Security Specialist)**: Monitoring, logging, and runtime security domain (~20%) covers attack path analysis, RBAC assessment, and threat modeling concepts that KubeHound demonstrates.
- **KCSA (Kubernetes and Cloud Native Security Associate)**: Threat modeling and MITRE ATT&CK framework knowledge are relevant exam topics.

## Learn More

- [Official docs](https://kubehound.io/)
- [GitHub repository](https://github.com/DataDog/KubeHound)
- [MITRE ATT&CK for Containers](https://attack.mitre.org/matrices/enterprise/containers/)
