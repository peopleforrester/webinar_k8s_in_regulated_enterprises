# KubeHound Configuration

KubeHound maps Kubernetes attack paths using graph analysis. It ingests
cluster state and builds an attack graph showing how an attacker could
escalate privileges.

## Prerequisites

- Docker and Docker Compose installed
- kubectl configured for target cluster

## Running KubeHound

```bash
# Start KubeHound with graph database
docker compose up -d

# Ingest cluster data
docker compose exec kubehound kubehound

# Access the graph UI (JanusGraph/Gremlin)
# Open http://localhost:8182 for Gremlin console
```

## Pre-Built Queries

The `queries/` directory contains Cypher queries for common attack path analysis:

- `attack-paths.cypher` - General attack path discovery
- `privilege-escalation.cypher` - Privilege escalation paths
- `identity-attacks.cypher` - Identity and credential attack paths

## Demo Usage

```bash
# After ingesting cluster data, run queries:
docker compose exec kubehound \
  kubehound query --file /queries/attack-paths.cypher

# Show all paths from compromised pod to cluster-admin
docker compose exec kubehound \
  kubehound query --file /queries/privilege-escalation.cypher
```
