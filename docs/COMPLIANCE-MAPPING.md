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
