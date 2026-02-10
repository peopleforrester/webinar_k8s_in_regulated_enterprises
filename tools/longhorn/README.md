# Longhorn

> **CNCF Status:** Incubating
> **Category:** Distributed Block Storage
> **Difficulty:** Intermediate
> **AKS Compatibility:** Supported (alternative to Azure Disk CSI)

## What It Does

Longhorn is a cloud-native distributed block storage system for Kubernetes, built
by Rancher/SUSE and donated to the CNCF. It provides highly available persistent
volumes by synchronously replicating data across multiple nodes, with built-in
snapshot, backup, and disaster recovery capabilities. Longhorn exposes storage via
a standard CSI driver, making it transparent to workloads that consume
PersistentVolumeClaims.

## Why Longhorn on AKS?

Azure Disk CSI is the default block storage on AKS and works well for most
workloads. Longhorn provides additional capabilities that matter in regulated
environments:

- **Multi-cloud portability** -- Storage configuration, backup policies, and
  encryption settings are identical across AKS, EKS, and GKE. No vendor lock-in
  on data durability guarantees.
- **Fine-grained replication control** -- Choose per-volume replica count (2 or 3)
  rather than relying on Azure's zone-redundant storage abstraction. You know
  exactly where your replicas live.
- **Built-in backup to Azure Blob** -- Native backup to Azure Blob Storage (or S3,
  or GCS) without requiring Velero or a separate backup tool for volume data.
- **Volume-level encryption** -- Encrypt individual volumes with per-volume keys,
  separate from the node-level encryption that Azure provides.
- **Snapshot scheduling** -- Recurring snapshots and backups with retention policies
  are built into Longhorn, not bolted on.

## Regulatory Relevance

| Framework   | Controls Addressed                                                                  |
|-------------|-------------------------------------------------------------------------------------|
| NCUA/FFIEC  | Data protection and backup requirements (Part 748 Appendix A/B)                     |
| SOC 2       | CC6.1 data protection controls, A1.2 backup and recovery mechanisms                 |
| DORA        | Article 11 (ICT data integrity management), Article 12 (backup and recovery policy) |
| PCI-DSS     | Requirement 3 (protect stored cardholder data), Requirement 12.10 (DR planning)     |

## Architecture

Longhorn deploys three core components plus a CSI driver that integrates with the
Kubernetes storage subsystem:

```
+-----------------------------------------------------------------------+
|  AKS Cluster                                                          |
|                                                                       |
|  +---------------------------+    +---------------------------+       |
|  | Node A                    |    | Node B                    |       |
|  |                           |    |                           |       |
|  |  +---------------------+ |    |  +---------------------+  |       |
|  |  | longhorn-manager    | |    |  | longhorn-manager    |  |       |
|  |  | (DaemonSet pod)     | |    |  | (DaemonSet pod)     |  |       |
|  |  +---------------------+ |    |  +---------------------+  |       |
|  |                           |    |                           |       |
|  |  +---------------------+ |    |  +---------------------+  |       |
|  |  | longhorn-engine     | |    |  | longhorn-engine     |  |       |
|  |  | (volume controller) | |    |  | (replica)           |  |       |
|  |  +---------------------+ |    |  +---------------------+  |       |
|  +---------------------------+    +---------------------------+       |
|                                                                       |
|  +---------------------------+    +---------------------------+       |
|  | Node C                    |    | longhorn-ui (Deployment)  |       |
|  |                           |    | Web dashboard for ops     |       |
|  |  +---------------------+ |    +---------------------------+       |
|  |  | longhorn-manager    | |                                         |
|  |  | (DaemonSet pod)     | |    +---------------------------+       |
|  |  +---------------------+ |    | CSI Driver (DaemonSet)    |       |
|  |                           |    | Mounts volumes into pods  |       |
|  |  +---------------------+ |    +---------------------------+       |
|  |  | longhorn-engine     | |                                         |
|  |  | (replica)           | |    +---------------------------+       |
|  |  +---------------------+ |    | Backup Target             |       |
|  +---------------------------+    | (Azure Blob / S3 / NFS)   |       |
|                                    +---------------------------+       |
+-----------------------------------------------------------------------+
```

- **longhorn-manager** -- DaemonSet on every node. Orchestrates volume creation,
  replica placement, snapshot scheduling, and backup operations. Exposes the
  Longhorn API.
- **longhorn-engine** -- Per-volume process. One controller (read/write head) and
  N-1 replicas (synchronous copies). Runs as instance-manager pods on each node
  that hosts volume data.
- **longhorn-ui** -- Optional web dashboard for volume management, backup monitoring,
  and node health. Disabled by default in production; use `kubectl port-forward`
  for on-demand access.
- **CSI driver** -- DaemonSet that implements the Container Storage Interface,
  letting Kubernetes mount Longhorn volumes into pods via standard PVC/PV bindings.

Data flow: **Pod writes to PVC** -> **CSI driver** -> **longhorn-engine controller**
-> **synchronous replication to N replicas across nodes** -> **periodic snapshots
and backups to Azure Blob Storage**.

## Quick Start (AKS)

### Prerequisites

- AKS cluster running (see [infrastructure/terraform](../../infrastructure/terraform/))
- Helm 3.x installed
- kubectl configured for the target cluster
- `open-iscsi` available on nodes (Ubuntu nodes include this by default; AzureLinux
  nodes may need the package installed -- see note below)

### Install

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update

helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  -f values.yaml
```

### Verify

```bash
# Confirm all Longhorn pods are running
kubectl get pods -n longhorn-system

# Check that the Longhorn StorageClass was created
kubectl get storageclass | grep longhorn

# Verify node readiness via Longhorn manager
kubectl get nodes.longhorn.io -n longhorn-system

# Access the Longhorn UI (on-demand)
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

### AzureLinux Node Note

AKS clusters using AzureLinux (CBL-Mariner) as the node OS may not have `open-iscsi`
pre-installed. Longhorn requires iSCSI for volume attachment. Verify with:

```bash
kubectl get pods -n longhorn-system -l app=longhorn-manager -o wide
kubectl logs -n longhorn-system <manager-pod> | grep -i iscsi
```

If iSCSI is missing, use a DaemonSet to install it or switch to Ubuntu-based node
pools. The Longhorn documentation provides an
[environment check script](https://longhorn.io/docs/latest/deploy/install/#installation-requirements)
for validation.

## Key Configuration Decisions

All configuration lives in [`values.yaml`](./values.yaml). Key decisions:

### Replica Count: 3

Three synchronous replicas spread across nodes provide tolerance for a single node
failure without data loss. Two replicas save storage but risk data loss if both
replica nodes fail simultaneously. For regulated workloads where data durability
is non-negotiable, three replicas is the minimum.

### Backup Target: Azure Blob Storage

Longhorn backs up volume data to Azure Blob Storage using a credential Secret. This
provides geographic redundancy beyond what in-cluster replication offers. Backups
are incremental (only changed blocks), keeping costs manageable. The backup target
is configured in `defaultSettings.backupTarget` and credential access is via a
Kubernetes Secret referenced in `defaultSettings.backupTargetCredentialSecret`.

### Guaranteed Instance Manager CPU

The `guaranteedInstanceManagerCPU` setting reserves CPU for Longhorn's engine and
replica processes. Without this reservation, noisy neighbors on the same node can
starve I/O operations, causing volume latency spikes. Set to 12% per manager in
demo; increase to 15-25% in production.

### Volume Encryption

The `regulated-encrypted` StorageClass in [`manifests/storage-class.yaml`](./manifests/storage-class.yaml)
enables per-volume LUKS encryption. Each volume gets its own encryption key stored
in a Kubernetes Secret. This provides defense-in-depth: even if node-level disk
encryption is compromised, individual volume data remains protected.

### ServiceMonitor: Disabled

Enable when prometheus-operator is installed in the cluster. Longhorn exposes
metrics for volume health, replica status, backup success/failure, and I/O
performance. See `values.yaml` for the full metrics list.

## Manifests

This directory includes example manifests for common Longhorn configurations:

- [`manifests/storage-class.yaml`](./manifests/storage-class.yaml) -- Standard and
  encrypted StorageClasses with educational comments
- [`manifests/pvc-example.yaml`](./manifests/pvc-example.yaml) -- PVC and Pod
  examples demonstrating volume lifecycle
- [`manifests/recurring-job.yaml`](./manifests/recurring-job.yaml) -- Automated
  snapshot and backup schedules with retention policies

## EKS / GKE Notes

- **EKS**: Longhorn installs identically on EKS. Change `backupTarget` from
  `azblob://` to `s3://` and use an IAM role for service account (IRSA) instead of
  the Azure credential Secret. Amazon Linux 2 and Bottlerocket nodes support
  iSCSI. EBS CSI is the EKS-native alternative, analogous to Azure Disk CSI.
- **GKE**: Longhorn works on GKE Standard clusters. Change `backupTarget` to
  `gs://` (Google Cloud Storage). GKE Autopilot clusters restrict DaemonSets and
  host access, making Longhorn incompatible -- use GCE Persistent Disk CSI instead.
  Ensure `open-iscsi` is available on Container-Optimized OS nodes.
- **General**: The Longhorn StorageClasses, recurring jobs, and PVC configurations
  are identical across all providers. Only the backup target URL and credential
  Secret format change.

## Certification Relevance

| Certification | Relevance                                                                          |
|---------------|------------------------------------------------------------------------------------|
| **CKA**       | Storage is ~10% of the CKA exam. PersistentVolumes, PersistentVolumeClaims, StorageClasses, and CSI driver concepts are core topics. Longhorn demonstrates all of these. |
| **KCNA**      | Covers Kubernetes storage concepts at a high level -- understanding what distributed storage provides and why it matters for stateful workloads. |
| **CKS**       | Volume encryption and backup security are relevant to the data protection domain. |

## Learn More

- [Longhorn documentation](https://longhorn.io/docs/)
- [CNCF project page](https://www.cncf.io/projects/longhorn/)
- [GitHub repository](https://github.com/longhorn/longhorn)
- [Helm chart repository](https://github.com/longhorn/charts)
- [Longhorn architecture](https://longhorn.io/docs/latest/concepts/)
- [Backup and restore guide](https://longhorn.io/docs/latest/snapshots-and-backups/)
