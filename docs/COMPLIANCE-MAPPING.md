# Compliance Mapping

Maps security controls in this repository to regulatory frameworks for
financial services environments.

## Kyverno Policies → Regulatory Requirements

| Kyverno Policy | NCUA | OSFI B-13 | DORA |
|---------------|------|-----------|------|
| disallow-privileged-containers | Cybersecurity Controls - Least Privilege | Section 4.3 - Access Controls | Article 9 - ICT Risk Management |
| require-run-as-nonroot | Cybersecurity Controls - Least Privilege | Section 4.3.2 - Least Privilege Access | Article 9(4)(c) - Access Control Policies |
| disallow-latest-tag | Change Management Controls | Section 5.2 - Configuration Management | Article 9(4)(e) - Change Management |
| require-resource-limits | Operational Resilience | Section 6.1 - Capacity Management | Article 11 - ICT Capacity and Performance |
| require-image-digest | Supply Chain Risk Management | OSFI B-10 Section 4.1 - Third Party Risk | Article 28 - ICT Third-Party Risk |
| require-readonly-rootfs | Container Hardening | Section 4.3 - System Hardening | Article 9(2) - Protection and Prevention |

## Falco Rules → MITRE ATT&CK Techniques

| Falco Rule | MITRE Technique | Tactic | Description |
|-----------|----------------|--------|-------------|
| Access Financial Data Files | - | Data Access | Detects access to files matching financial data patterns (account, credit, SSN) |
| Container Accessing K8s Secrets | T1552.007 | Credential Access | Container querying Kubernetes secrets API |
| Read Service Account Token | T1552.001 | Credential Access | Process reading mounted SA token files |
| Detect Crypto Mining Process | T1496 | Impact | Known mining binaries or stratum protocol connections |
| Outbound Connection to Non-Standard Port | T1041 | Exfiltration | Container connecting to non-standard TCP ports |
| Container Privilege Escalation | T1548 | Privilege Escalation | Use of sudo/su or writes to /etc/passwd, /etc/shadow |
| Terminal Shell in Container | T1059 | Execution | Interactive shell spawned inside container |
| Kubectl Exec Detected | T1609 | Execution | External exec session into running container |
| Database Credential File Access | T1552.001 | Credential Access | Access to .pgpass, .my.cnf, database.yml files |

## Kubescape Frameworks → Regulatory Requirements

| Framework | Regulatory Mapping | Key Controls |
|-----------|-------------------|--------------|
| NSA Kubernetes Hardening | NCUA Cybersecurity, OSFI B-13 Section 4 | Pod security, network policies, authentication, audit logging |
| SOC2 | NCUA Operational Controls | Access control, monitoring, change management, risk assessment |
| MITRE ATT&CK | NCUA Threat Detection, OSFI B-13 Section 5 | Detection coverage across attack lifecycle |
| CIS Kubernetes Benchmark | OSFI B-13 Section 4.3, DORA Article 9 | API server, etcd, kubelet, network hardening |

## Trivy Scanning → Vulnerability Management

| Scan Type | Regulatory Requirement | SLA |
|-----------|----------------------|-----|
| Critical Vulnerabilities | NCUA - Immediate remediation required | 24 hours |
| High Vulnerabilities | OSFI B-13 Section 5.1 - Patch Management | 7 days |
| Medium Vulnerabilities | DORA Article 9(4)(d) - Security Updates | 30 days |
| Low Vulnerabilities | Tracked and reviewed quarterly | 90 days |
| SBOM Generation | DORA Article 28 - Supply Chain Transparency | Per release |

## Istio (Service Mesh) → Regulatory Requirements

| Istio Feature | NCUA | OSFI B-13 | DORA |
|--------------|------|-----------|------|
| Mutual TLS (mTLS) | Data Encryption in Transit | Section 4.3 - Cryptographic Controls | Article 9(4)(b) - Encryption Policies |
| AuthorizationPolicy | Access Control - Least Privilege | Section 4.3.2 - Service Identity | Article 9(4)(c) - Access Control |
| PeerAuthentication | Identity Verification | Section 4.4 - Authentication | Article 9(2) - Protection and Prevention |
| Traffic Management | Operational Resilience | Section 6.1 - Continuity Planning | Article 11 - Business Continuity |

## ArgoCD (GitOps) → Regulatory Requirements

| ArgoCD Feature | NCUA | OSFI B-13 | DORA |
|---------------|------|-----------|------|
| Git-based Deployments | Change Management Audit Trail | Section 5.2 - Configuration Management | Article 9(4)(e) - Change Management |
| Application Sync | Continuous Compliance Verification | Section 4.5 - Continuous Monitoring | Article 10 - Detection |
| RBAC (Projects) | Separation of Duties | Section 4.3 - Access Controls | Article 9(4)(c) - Access Control |
| Audit Logging | Incident Investigation | Section 5.3 - Logging and Monitoring | Article 17 - ICT Incident Reporting |

## External Secrets → Regulatory Requirements

| ESO Feature | NCUA | OSFI B-13 | DORA |
|------------|------|-----------|------|
| Key Vault Sync | Secrets Management - Centralized | Section 4.3 - Cryptographic Key Management | Article 9(4)(b) - Encryption |
| Secret Rotation | Credential Lifecycle Management | Section 4.3.3 - Key Rotation | Article 9(4)(d) - Security Updates |
| ClusterSecretStore | Audit Trail for Secret Access | Section 5.3 - Access Logging | Article 17 - Incident Reporting |

## Crossplane → Regulatory Requirements

| Crossplane Feature | NCUA | OSFI B-13 | DORA |
|-------------------|------|-----------|------|
| Declarative Infra | Infrastructure Audit Trail | Section 5.2 - Configuration Management | Article 9(4)(e) - Change Management |
| Drift Detection | Configuration Compliance | Section 4.5 - Continuous Monitoring | Article 10 - Detection |
| RBAC on Resources | Infrastructure Access Control | Section 4.3 - Access Controls | Article 9(4)(c) - Access Control |

## Harbor → Regulatory Requirements

| Harbor Feature | NCUA | OSFI B-13 | DORA |
|---------------|------|-----------|------|
| Image Scanning | Supply Chain Vulnerability Mgmt | Section 5.1 - Vulnerability Management | Article 9(4)(d) - Security Updates |
| Content Trust (Notary) | Image Integrity Verification | OSFI B-10 Section 4.1 - Third Party Risk | Article 28 - Supply Chain |
| RBAC / Projects | Registry Access Control | Section 4.3 - Access Controls | Article 9(4)(c) - Access Control |
| Audit Logs | Image Pull/Push Audit Trail | Section 5.3 - Logging | Article 17 - ICT Incident Reporting |

## Karpenter → Regulatory Requirements

| Karpenter Feature | NCUA | OSFI B-13 | DORA |
|------------------|------|-----------|------|
| Node Autoscaling | Capacity Management | Section 6.1 - Capacity Planning | Article 11 - Capacity and Performance |
| Spot Instance Mgmt | Cost Optimization | Section 6.2 - Financial Controls | Article 12 - Proportionality |
| Consolidation | Resource Efficiency | Section 6.1 - Operational Efficiency | Article 11 - Performance Management |

## Regulatory Framework Reference

### NCUA (National Credit Union Administration)
- Supervisory priorities for cybersecurity controls
- FFIEC Cloud Computing guidance
- Information security examination procedures

### OSFI (Office of the Superintendent of Financial Institutions - Canada)
- **B-10**: Third-Party Risk Management
- **B-13**: Technology and Cyber Risk Management
- **E-23**: Model Risk Management (for AI workloads)

### DORA (Digital Operational Resilience Act - EU)
- **Article 5-15**: ICT Risk Management Framework
- **Article 17-23**: ICT Incident Reporting
- **Article 24-27**: Digital Operational Resilience Testing
- **Article 28-44**: ICT Third-Party Risk Management
