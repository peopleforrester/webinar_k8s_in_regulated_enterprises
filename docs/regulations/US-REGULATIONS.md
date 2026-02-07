# US Financial Regulations for Kubernetes Security

> A comprehensive guide for platform engineers implementing container security controls in regulated financial services environments

## Table of Contents

1. [Overview](#overview)
2. [NCUA - National Credit Union Administration](#ncua---national-credit-union-administration)
3. [FFIEC - Federal Financial Institutions Examination Council](#ffiec---federal-financial-institutions-examination-council)
4. [Demo Tool Mapping Summary](#demo-tool-mapping-summary)
5. [Implementation Checklist](#implementation-checklist)
6. [Additional Resources](#additional-resources)

---

## Overview

This document provides detailed guidance on how US financial regulations apply to Kubernetes and container security implementations. The regulations covered here establish requirements that directly impact how platform engineers design, deploy, and operate containerized workloads in financial services environments.

### Why This Matters for Kubernetes

Container orchestration platforms like Kubernetes introduce unique security considerations:

- **Ephemeral workloads** require continuous security monitoring
- **Shared infrastructure** demands strong isolation controls
- **Declarative configurations** enable policy-as-code approaches
- **Complex supply chains** necessitate comprehensive vulnerability scanning
- **Dynamic environments** require automated compliance verification

### Regulations Covered

| Regulation | Governing Body | Primary Focus |
|------------|----------------|---------------|
| NCUA Guidelines | National Credit Union Administration | Credit union cybersecurity and operational resilience |
| FFIEC Guidance | Federal Financial Institutions Examination Council | Interagency technology and cloud computing standards |

---

## NCUA - National Credit Union Administration

### Full Name and Governing Body

**National Credit Union Administration (NCUA)**

The NCUA is an independent federal agency that regulates, charters, and supervises federal credit unions. The agency insures deposits at federally insured credit unions through the National Credit Union Share Insurance Fund (NCUSIF).

- **Established:** 1970
- **Jurisdiction:** All federally chartered credit unions and most state-chartered credit unions
- **Website:** [https://www.ncua.gov](https://www.ncua.gov)

### Effective Dates and Recent Updates

| Document | Effective Date | Last Updated | Status |
|----------|---------------|--------------|--------|
| NCUA Supervisory Priorities | Annual (January) | January 2026 | Active |
| NCUA Cybersecurity Resources | Ongoing | December 2025 | Active |
| NCUA Examiner's Guide - IT | Ongoing | October 2025 | Active |
| Interagency Guidelines (Part 748) | 2005 | March 2024 | Active |

### Key Regulatory Documents

1. **Supervisory Letter 21-01: Cybersecurity**
   - Establishes expectations for credit union cybersecurity programs
   - Emphasizes risk-based approach to technology management
   - URL: [https://www.ncua.gov/regulation-supervision/letters-credit-unions-other-guidance/supervisory-priorities](https://www.ncua.gov/regulation-supervision/letters-credit-unions-other-guidance/supervisory-priorities)

2. **12 CFR Part 748 - Security Programs**
   - Requires written security programs
   - Mandates access controls and monitoring
   - URL: [https://www.ecfr.gov/current/title-12/chapter-VII/subchapter-A/part-748](https://www.ecfr.gov/current/title-12/chapter-VII/subchapter-A/part-748)

3. **ACET (Automated Cybersecurity Examination Tool)**
   - Self-assessment tool based on FFIEC CAT
   - Baseline cybersecurity controls
   - URL: [https://www.ncua.gov/regulation-supervision/regulatory-compliance-resources/cybersecurity-resources](https://www.ncua.gov/regulation-supervision/regulatory-compliance-resources/cybersecurity-resources)

### Key Requirements Relevant to Kubernetes/Container Security

#### 1. Access Controls and Least Privilege

**Regulatory Requirement:**
> "Credit unions must implement access controls that limit user access to information systems and data to the minimum necessary to perform job functions."
> - 12 CFR 748 Appendix A

**Kubernetes Application:**

| NCUA Requirement | Kubernetes Control | Implementation |
|-----------------|-------------------|----------------|
| Role-based access | RBAC | Define ClusterRoles and RoleBindings with minimum permissions |
| Separation of duties | Namespace isolation | Separate workloads by function using namespaces |
| Privileged access management | PodSecurityContext | Enforce non-root containers, drop capabilities |
| Service account controls | ServiceAccount + RBAC | Limit pod service account permissions |

**Demo Tool Mapping:**

| Tool | How It Addresses Requirement |
|------|------------------------------|
| **Kyverno** | Enforces `require-run-as-nonroot` policy, blocking privileged containers |
| **Kyverno** | Policy `disallow-privileged-containers` prevents privilege escalation |
| **Kubescape** | NSA/CISA framework checks for excessive permissions |
| **KubeHound** | Visualizes attack paths from over-permissioned service accounts |

#### 2. Continuous Monitoring and Threat Detection

**Regulatory Requirement:**
> "Credit unions should implement continuous monitoring capabilities to detect unauthorized access, use, or modifications to information systems."
> - NCUA Supervisory Priorities 2026

**Kubernetes Application:**

| NCUA Requirement | Kubernetes Control | Implementation |
|-----------------|-------------------|----------------|
| Real-time monitoring | Runtime security | Deploy Falco for syscall monitoring |
| Anomaly detection | Behavioral analysis | Custom Falco rules for financial data access |
| Audit logging | Kubernetes audit logs | Enable API server audit logging |
| Incident alerting | Alert integration | Falcosidekick for alert routing |

**Demo Tool Mapping:**

| Tool | How It Addresses Requirement |
|------|------------------------------|
| **Falco** | Real-time detection of suspicious container behavior |
| **Falco** | Custom rules detect credential theft, crypto mining, privilege escalation |
| **Falco** | MITRE ATT&CK tagged alerts for incident classification |
| **Kubescape** | Continuous posture scanning with drift detection |

#### 3. Vulnerability Management

**Regulatory Requirement:**
> "Credit unions must establish and maintain a vulnerability management program that includes identification, assessment, and remediation of vulnerabilities."
> - NCUA Examiner's Guide - Information Technology

**Kubernetes Application:**

| NCUA Requirement | Kubernetes Control | Implementation |
|-----------------|-------------------|----------------|
| Vulnerability scanning | Image scanning | Scan images before deployment |
| Risk assessment | CVE prioritization | Focus on critical/high CVEs with EPSS scores |
| Patch management | Image updates | Automated base image updates |
| Configuration assessment | CIS benchmarks | Regular benchmark scans |

**Demo Tool Mapping:**

| Tool | How It Addresses Requirement |
|------|------------------------------|
| **Trivy** | Container image vulnerability scanning |
| **Trivy** | SBOM generation for software inventory |
| **Trivy** | Kubernetes manifest misconfiguration detection |
| **Kubescape** | NSA, CIS, and MITRE framework compliance scanning |
| **Kyverno** | Policy `require-image-digest` ensures image integrity |

#### 4. Configuration Management

**Regulatory Requirement:**
> "Credit unions must maintain secure configurations for all system components and ensure configurations are documented, approved, and monitored for unauthorized changes."
> - 12 CFR 748 Appendix B

**Kubernetes Application:**

| NCUA Requirement | Kubernetes Control | Implementation |
|-----------------|-------------------|----------------|
| Secure baselines | Pod Security Standards | Enforce restricted PSS profile |
| Configuration documentation | GitOps | Store all configs in version control |
| Change detection | Admission control | Validate all changes at admission |
| Drift prevention | Policy enforcement | Continuous policy scanning |

**Demo Tool Mapping:**

| Tool | How It Addresses Requirement |
|------|------------------------------|
| **Kyverno** | Policy-as-code for configuration standards |
| **Kyverno** | `require-resource-limits` enforces resource boundaries |
| **Kyverno** | `require-readonly-rootfs` hardens container filesystem |
| **Kubescape** | Detects configuration drift from security baselines |

### Specific NCUA Sections Applicable to This Demo

#### 12 CFR 748 Appendix A - Guidelines for Safeguarding Member Information

| Section | Requirement | Demo Implementation |
|---------|-------------|---------------------|
| III.B.1 | Access controls based on job function | Kyverno RBAC policies, namespace isolation |
| III.B.2 | Physical/logical access restrictions | Network policies, pod security contexts |
| III.C.1 | Monitor systems for attacks | Falco runtime detection |
| III.C.2 | Response procedures | Falcosidekick alerting integration |
| III.D | Oversee service providers | Trivy for third-party image scanning |

#### NCUA Supervisory Priorities 2026 - Cybersecurity

| Priority Area | Demo Coverage |
|--------------|---------------|
| Ransomware prevention | Falco detects crypto mining and suspicious processes |
| Phishing/social engineering | Out of scope (network-level) |
| Third-party risk | Trivy SBOM, vulnerability scanning |
| Cloud security | Kubescape cloud-native compliance frameworks |
| Zero Trust implementation | Kyverno admission control, network policies |

### Official Documentation Links

- NCUA Homepage: [https://www.ncua.gov](https://www.ncua.gov)
- Cybersecurity Resources: [https://www.ncua.gov/regulation-supervision/regulatory-compliance-resources/cybersecurity-resources](https://www.ncua.gov/regulation-supervision/regulatory-compliance-resources/cybersecurity-resources)
- Letters to Credit Unions: [https://www.ncua.gov/regulation-supervision/letters-credit-unions-other-guidance](https://www.ncua.gov/regulation-supervision/letters-credit-unions-other-guidance)
- 12 CFR Part 748: [https://www.ecfr.gov/current/title-12/chapter-VII/subchapter-A/part-748](https://www.ecfr.gov/current/title-12/chapter-VII/subchapter-A/part-748)
- ACET Tool: [https://www.ncua.gov/regulation-supervision/regulatory-compliance-resources/cybersecurity-resources/automated-cybersecurity-evaluation-toolbox](https://www.ncua.gov/regulation-supervision/regulatory-compliance-resources/cybersecurity-resources/automated-cybersecurity-evaluation-toolbox)

---

## FFIEC - Federal Financial Institutions Examination Council

### Full Name and Governing Body

**Federal Financial Institutions Examination Council (FFIEC)**

The FFIEC is a formal interagency body empowered to prescribe uniform principles, standards, and report forms for the federal examination of financial institutions.

**Member Agencies:**
- Board of Governors of the Federal Reserve System (FRB)
- Federal Deposit Insurance Corporation (FDIC)
- National Credit Union Administration (NCUA)
- Office of the Comptroller of the Currency (OCC)
- Consumer Financial Protection Bureau (CFPB)
- State Liaison Committee (SLC)

- **Established:** 1979
- **Jurisdiction:** All federally supervised financial institutions
- **Website:** [https://www.ffiec.gov](https://www.ffiec.gov)

### Effective Dates and Recent Updates

| Document | Effective Date | Last Updated | Status |
|----------|---------------|--------------|--------|
| IT Examination Handbook - Information Security | 2016 | November 2024 | Active |
| IT Examination Handbook - Architecture, Infrastructure, and Operations | 2021 | August 2025 | Active |
| Cloud Computing Statement | 2020 | 2020 | Active |
| Third-Party Risk Management Guidance | 2023 | June 2023 | Active |
| Cybersecurity Assessment Tool (CAT) | 2015 | September 2024 | Active |

### Key Regulatory Documents

1. **IT Examination Handbook - Information Security Booklet**
   - Comprehensive guidance on information security programs
   - Covers authentication, access control, network security
   - URL: [https://ithandbook.ffiec.gov/it-booklets/information-security.aspx](https://ithandbook.ffiec.gov/it-booklets/information-security.aspx)

2. **IT Examination Handbook - Architecture, Infrastructure, and Operations (AIO) Booklet**
   - Guidance on IT architecture and operations
   - Includes virtualization and containerization
   - URL: [https://ithandbook.ffiec.gov/it-booklets/architecture,-infrastructure,-and-operations.aspx](https://ithandbook.ffiec.gov/it-booklets/architecture,-infrastructure,-and-operations.aspx)

3. **Joint Statement on Security in a Cloud Computing Environment**
   - Specific guidance for cloud adoption
   - Risk management considerations
   - URL: [https://www.ffiec.gov/press/PDF/FFIEC_Cloud_Computing_Statement.pdf](https://www.ffiec.gov/press/PDF/FFIEC_Cloud_Computing_Statement.pdf)

4. **Interagency Guidance on Third-Party Relationships: Risk Management**
   - Managing risks from service providers
   - Due diligence and monitoring requirements
   - URL: [https://www.occ.gov/news-issuances/bulletins/2023/bulletin-2023-17.html](https://www.occ.gov/news-issuances/bulletins/2023/bulletin-2023-17.html)

5. **Cybersecurity Assessment Tool (CAT)**
   - Self-assessment for cybersecurity preparedness
   - Maturity model across five domains
   - URL: [https://www.ffiec.gov/cyberassessmenttool.htm](https://www.ffiec.gov/cyberassessmenttool.htm)

### Key Requirements Relevant to Kubernetes/Container Security

#### 1. Cloud Computing Security

**Regulatory Requirement (FFIEC Cloud Statement):**
> "Financial institutions should implement robust security controls when using cloud computing services, including strong access controls, encryption, and continuous monitoring."

**Kubernetes Application:**

| FFIEC Requirement | Kubernetes Control | Implementation |
|------------------|-------------------|----------------|
| Data encryption in transit | mTLS/service mesh | Enable pod-to-pod encryption |
| Data encryption at rest | Secrets encryption | Enable etcd encryption |
| Multi-tenancy isolation | Namespace/network policies | Strict namespace boundaries |
| Logging and monitoring | Centralized logging | Export logs to SIEM |
| Incident response | Alerting pipelines | Automated threat notification |

**Demo Tool Mapping:**

| Tool | How It Addresses Requirement |
|------|------------------------------|
| **Falco** | Continuous runtime monitoring for cloud workloads |
| **Kyverno** | Admission control for consistent security policies |
| **Kubescape** | Cloud security posture management (CSPM) capabilities |
| **Trivy** | Scans cloud-native configurations for misconfigurations |

#### 2. Third-Party Risk Management

**Regulatory Requirement (Interagency Guidance):**
> "A financial institution should have risk management processes that are commensurate with the level of risk and complexity of its third-party relationships."

**Kubernetes Application:**

| FFIEC Requirement | Kubernetes Control | Implementation |
|------------------|-------------------|----------------|
| Vendor assessment | Supply chain security | Verify image sources and signatures |
| Ongoing monitoring | Continuous scanning | Regular vulnerability rescans |
| Software inventory | SBOM generation | Maintain software bill of materials |
| Contract management | Policy enforcement | Enforce approved registries |

**Demo Tool Mapping:**

| Tool | How It Addresses Requirement |
|------|------------------------------|
| **Trivy** | SBOM generation in CycloneDX/SPDX formats |
| **Trivy** | Vulnerability scanning of third-party images |
| **Kyverno** | `require-image-digest` ensures image provenance |
| **Kyverno** | Registry allowlisting policies |
| **Kubescape** | Supply chain security controls verification |

#### 3. Access Controls and Authentication

**Regulatory Requirement (Information Security Booklet, Section II.C.5):**
> "Access rights should be based on the concept of least privilege and the need to know. The institution should have policies and procedures to create, modify, and terminate access."

**Kubernetes Application:**

| FFIEC Requirement | Kubernetes Control | Implementation |
|------------------|-------------------|----------------|
| Least privilege | RBAC | Minimal role definitions |
| Privileged access | Admission control | Block privileged containers |
| User identification | ServiceAccounts | Unique identities per workload |
| Access reviews | Audit logs | Regular permission reviews |
| Termination procedures | Automated cleanup | RBAC tied to identity provider |

**Demo Tool Mapping:**

| Tool | How It Addresses Requirement |
|------|------------------------------|
| **Kyverno** | `disallow-privileged-containers` enforces least privilege |
| **Kyverno** | `require-run-as-nonroot` prevents root access |
| **KubeHound** | Identifies excessive RBAC permissions and attack paths |
| **Kubescape** | Detects overly permissive RBAC configurations |

#### 4. Vulnerability and Patch Management

**Regulatory Requirement (AIO Booklet, Section III.B.5):**
> "Management should have effective policies, standards, and processes for identifying, measuring, mitigating, and monitoring vulnerabilities in systems."

**Kubernetes Application:**

| FFIEC Requirement | Kubernetes Control | Implementation |
|------------------|-------------------|----------------|
| Vulnerability identification | Image scanning | Scan at build and runtime |
| Risk prioritization | CVE analysis | Focus on exploitable vulnerabilities |
| Patch deployment | Rolling updates | Zero-downtime patching |
| Compensating controls | Runtime protection | Detect exploitation attempts |

**Demo Tool Mapping:**

| Tool | How It Addresses Requirement |
|------|------------------------------|
| **Trivy** | CVE scanning with severity classification |
| **Trivy** | Exploitability analysis (EPSS scores) |
| **Falco** | Runtime detection of vulnerability exploitation |
| **Kubescape** | Workload vulnerability risk assessment |

#### 5. Secure Development and Configuration

**Regulatory Requirement (Information Security Booklet, Section II.C.20):**
> "Management should implement and enforce secure software development practices and maintain secure configurations for all systems."

**Kubernetes Application:**

| FFIEC Requirement | Kubernetes Control | Implementation |
|------------------|-------------------|----------------|
| Secure coding | Container hardening | Minimal base images |
| Code review | GitOps workflows | PR-based deployments |
| Configuration standards | Pod Security Standards | Enforce restricted profiles |
| Change management | Admission control | Validate all deployments |

**Demo Tool Mapping:**

| Tool | How It Addresses Requirement |
|------|------------------------------|
| **Kyverno** | Policy-as-code for deployment standards |
| **Kyverno** | `disallow-latest-tag` enforces version pinning |
| **Kyverno** | `require-resource-limits` prevents resource exhaustion |
| **Trivy** | Dockerfile/manifest security scanning |
| **Kubescape** | CIS Kubernetes benchmark validation |

#### 6. Logging, Monitoring, and Incident Response

**Regulatory Requirement (Information Security Booklet, Section II.C.13):**
> "The institution should implement logging capabilities and monitor logs for security events. The institution should have an incident response program."

**Kubernetes Application:**

| FFIEC Requirement | Kubernetes Control | Implementation |
|------------------|-------------------|----------------|
| Security logging | Audit logs | Enable Kubernetes audit logging |
| Log monitoring | SIEM integration | Forward logs to central platform |
| Alert correlation | Alerting rules | Define security-focused alerts |
| Incident response | Playbooks | Automated response actions |
| Forensic capability | Log retention | Retain logs per policy |

**Demo Tool Mapping:**

| Tool | How It Addresses Requirement |
|------|------------------------------|
| **Falco** | Real-time security event detection |
| **Falco** | MITRE ATT&CK mapping for threat classification |
| **Falcosidekick** | Alert routing to SIEM, Slack, email |
| **Kubescape** | Scheduled compliance reporting |

### Specific FFIEC Handbook Sections Applicable to This Demo

#### Information Security Booklet

| Section | Title | Demo Implementation |
|---------|-------|---------------------|
| II.C.5 | Access Controls | Kyverno policies, RBAC |
| II.C.6 | Network Security | Network policies |
| II.C.7 | Host Security | Pod security contexts |
| II.C.8 | Application Security | Image scanning, admission control |
| II.C.11 | Data Security | Secrets management |
| II.C.13 | Monitoring and Logging | Falco runtime detection |
| II.C.18 | Vulnerability Management | Trivy scanning |

#### AIO Booklet

| Section | Title | Demo Implementation |
|---------|-------|---------------------|
| III.A.3 | Virtualization and Containers | Container security controls |
| III.B.2 | Infrastructure Resilience | Resource limits, health checks |
| III.B.5 | Patch Management | Image updates, rolling deployments |
| III.C.1 | Operations Security | Runtime monitoring |
| III.D.3 | Service Level Management | Compliance reporting |

#### Cybersecurity Assessment Tool (CAT) Domains

| Domain | Maturity Level Target | Demo Tools |
|--------|----------------------|------------|
| Cyber Risk Management and Oversight | Intermediate | Kubescape reporting |
| Threat Intelligence and Collaboration | Intermediate | Falco MITRE mapping |
| Cybersecurity Controls | Advanced | Kyverno, Falco, Trivy |
| External Dependency Management | Intermediate | Trivy SBOM |
| Cyber Incident Management and Resilience | Intermediate | Falcosidekick alerting |

### Official Documentation Links

- FFIEC Homepage: [https://www.ffiec.gov](https://www.ffiec.gov)
- IT Examination Handbook: [https://ithandbook.ffiec.gov](https://ithandbook.ffiec.gov)
- Information Security Booklet: [https://ithandbook.ffiec.gov/it-booklets/information-security.aspx](https://ithandbook.ffiec.gov/it-booklets/information-security.aspx)
- AIO Booklet: [https://ithandbook.ffiec.gov/it-booklets/architecture,-infrastructure,-and-operations.aspx](https://ithandbook.ffiec.gov/it-booklets/architecture,-infrastructure,-and-operations.aspx)
- Cloud Computing Statement: [https://www.ffiec.gov/press/PDF/FFIEC_Cloud_Computing_Statement.pdf](https://www.ffiec.gov/press/PDF/FFIEC_Cloud_Computing_Statement.pdf)
- Third-Party Risk Management: [https://www.occ.gov/news-issuances/bulletins/2023/bulletin-2023-17.html](https://www.occ.gov/news-issuances/bulletins/2023/bulletin-2023-17.html)
- Cybersecurity Assessment Tool: [https://www.ffiec.gov/cyberassessmenttool.htm](https://www.ffiec.gov/cyberassessmenttool.htm)

---

## Demo Tool Mapping Summary

### Comprehensive Tool-to-Requirement Matrix

| Demo Tool | NCUA Requirements Addressed | FFIEC Requirements Addressed |
|-----------|---------------------------|------------------------------|
| **Falco** | Continuous monitoring, threat detection, incident response | Logging/monitoring, incident response, intrusion detection |
| **Kyverno** | Access controls, least privilege, configuration management | Access controls, secure configuration, change management |
| **Kubescape** | Vulnerability management, compliance reporting | Security assessments, control validation, risk management |
| **Trivy** | Vulnerability scanning, third-party risk | Vulnerability management, supply chain security, SBOM |
| **KubeHound** | Access path analysis, privilege escalation detection | Access control validation, risk visualization |

### Tool Capabilities by Security Control Category

#### Policy Enforcement (Prevention)

```
┌─────────────────────────────────────────────────────────────────┐
│                          KYVERNO                                 │
├─────────────────────────────────────────────────────────────────┤
│  Policy                        │ NCUA Reference │ FFIEC Reference│
├────────────────────────────────┼────────────────┼────────────────┤
│  disallow-privileged-containers│ 12 CFR 748.A   │ IS-II.C.5      │
│  require-run-as-nonroot        │ 12 CFR 748.A   │ IS-II.C.5      │
│  disallow-latest-tag           │ ACET-4.2       │ IS-II.C.20     │
│  require-resource-limits       │ ACET-4.3       │ AIO-III.B.2    │
│  require-image-digest          │ ACET-4.2       │ IS-II.C.8      │
│  require-readonly-rootfs       │ 12 CFR 748.A   │ IS-II.C.7      │
└────────────────────────────────┴────────────────┴────────────────┘
```

#### Runtime Detection (Detection)

```
┌─────────────────────────────────────────────────────────────────┐
│                           FALCO                                  │
├─────────────────────────────────────────────────────────────────┤
│  Rule Category                 │ NCUA Reference │ FFIEC Reference│
├────────────────────────────────┼────────────────┼────────────────┤
│  Financial data access         │ 12 CFR 748.C.1 │ IS-II.C.11     │
│  Secrets/credential theft      │ 12 CFR 748.C.1 │ IS-II.C.5      │
│  Privilege escalation          │ 12 CFR 748.B.2 │ IS-II.C.7      │
│  Crypto mining                 │ ACET-4.1       │ IS-II.C.13     │
│  Suspicious network activity   │ 12 CFR 748.C.1 │ IS-II.C.6      │
│  Shell access                  │ 12 CFR 748.C.2 │ IS-II.C.13     │
└────────────────────────────────┴────────────────┴────────────────┘
```

#### Vulnerability Scanning (Assessment)

```
┌─────────────────────────────────────────────────────────────────┐
│                           TRIVY                                  │
├─────────────────────────────────────────────────────────────────┤
│  Scan Type                     │ NCUA Reference │ FFIEC Reference│
├────────────────────────────────┼────────────────┼────────────────┤
│  Container image CVEs          │ ACET-4.2       │ AIO-III.B.5    │
│  SBOM generation               │ ACET-4.1       │ TPRM-III.B     │
│  Kubernetes misconfigurations  │ 12 CFR 748.B.1 │ IS-II.C.20     │
│  Secret detection              │ 12 CFR 748.A   │ IS-II.C.11     │
│  License compliance            │ ACET-4.1       │ TPRM-III.A     │
└────────────────────────────────┴────────────────┴────────────────┘
```

#### Compliance Reporting (Governance)

```
┌─────────────────────────────────────────────────────────────────┐
│                         KUBESCAPE                                │
├─────────────────────────────────────────────────────────────────┤
│  Framework                     │ NCUA Reference │ FFIEC Reference│
├────────────────────────────────┼────────────────┼────────────────┤
│  NSA/CISA Hardening            │ ACET (all)     │ IS (all)       │
│  CIS Kubernetes Benchmark      │ 12 CFR 748.B   │ IS-II.C.20     │
│  MITRE ATT&CK                  │ 12 CFR 748.C   │ IS-II.C.13     │
│  SOC 2 Type II                 │ ACET-5.1       │ AIO-III.D      │
│  PCI-DSS (applicable controls) │ 12 CFR 748.A   │ IS-II.C.5      │
└────────────────────────────────┴────────────────┴────────────────┘
```

#### Attack Path Analysis (Risk)

```
┌─────────────────────────────────────────────────────────────────┐
│                         KUBEHOUND                                │
├─────────────────────────────────────────────────────────────────┤
│  Analysis Type                 │ NCUA Reference │ FFIEC Reference│
├────────────────────────────────┼────────────────┼────────────────┤
│  Privilege escalation paths    │ 12 CFR 748.B.1 │ IS-II.C.5      │
│  Service account risks         │ 12 CFR 748.B.2 │ IS-II.C.5      │
│  Node compromise scenarios     │ ACET-4.1       │ IS-II.C.7      │
│  Lateral movement vectors      │ 12 CFR 748.C.1 │ IS-II.C.6      │
│  Pod escape risks              │ ACET-4.1       │ IS-II.C.7      │
└────────────────────────────────┴────────────────┴────────────────┘
```

---

## Implementation Checklist

### Pre-Deployment Regulatory Compliance

Use this checklist to verify regulatory alignment before production deployment:

#### NCUA Compliance Checklist

- [ ] **Access Controls (12 CFR 748.A)**
  - [ ] RBAC configured with least privilege
  - [ ] Service accounts have minimal permissions
  - [ ] Network policies restrict pod-to-pod communication
  - [ ] Kyverno policies enforce non-root containers

- [ ] **Monitoring (12 CFR 748.C)**
  - [ ] Falco deployed and operational
  - [ ] Custom financial services rules loaded
  - [ ] Alerts routing to security team
  - [ ] MITRE ATT&CK tags in alert messages

- [ ] **Vulnerability Management (ACET)**
  - [ ] Trivy Operator installed
  - [ ] Automatic image scanning enabled
  - [ ] SBOM generation configured
  - [ ] Vulnerability reports accessible

- [ ] **Configuration Management**
  - [ ] Kyverno policies in enforce mode
  - [ ] Image digest requirements active
  - [ ] Resource limits enforced
  - [ ] Read-only root filesystem (where possible)

- [ ] **Compliance Reporting**
  - [ ] Kubescape scheduled scans configured
  - [ ] NSA/CISA framework selected
  - [ ] Reports exported to compliance team
  - [ ] Baseline compliance score documented

#### FFIEC Compliance Checklist

- [ ] **Cloud Security (FFIEC Statement)**
  - [ ] Encryption in transit (mTLS or service mesh)
  - [ ] Secrets encrypted at rest (etcd encryption)
  - [ ] Multi-tenancy isolation verified
  - [ ] Audit logging enabled

- [ ] **Third-Party Risk (Interagency Guidance)**
  - [ ] Container images from approved registries
  - [ ] SBOM generated for all images
  - [ ] Third-party vulnerabilities tracked
  - [ ] Supply chain attestations verified

- [ ] **Information Security (IS Booklet)**
  - [ ] All IS-II.C controls addressed
  - [ ] Kyverno policies mapped to requirements
  - [ ] Falco rules mapped to threats
  - [ ] Kubescape controls mapped to sections

- [ ] **Operations (AIO Booklet)**
  - [ ] Container security controls documented
  - [ ] Patch management process defined
  - [ ] Incident response procedures tested
  - [ ] Service level metrics tracked

---

## Additional Resources

### NCUA Resources

| Resource | Description | Link |
|----------|-------------|------|
| NCUA Examiner's Guide | Detailed examination procedures | [Guide](https://www.ncua.gov/regulation-supervision/manuals-guides) |
| Cybersecurity Resources | Tools and guidance | [Resources](https://www.ncua.gov/regulation-supervision/regulatory-compliance-resources/cybersecurity-resources) |
| Letters to Credit Unions | Supervisory guidance | [Letters](https://www.ncua.gov/regulation-supervision/letters-credit-unions-other-guidance) |
| ACET Download | Self-assessment tool | [ACET](https://www.ncua.gov/regulation-supervision/regulatory-compliance-resources/cybersecurity-resources/automated-cybersecurity-evaluation-toolbox) |

### FFIEC Resources

| Resource | Description | Link |
|----------|-------------|------|
| IT Handbook | Complete examination handbooks | [Handbook](https://ithandbook.ffiec.gov) |
| CAT Tool | Cybersecurity assessment | [CAT](https://www.ffiec.gov/cyberassessmenttool.htm) |
| Press Releases | New guidance announcements | [Press](https://www.ffiec.gov/press.htm) |
| Uniform Reporting | Reporting requirements | [Reporting](https://www.ffiec.gov/ubpr.htm) |

### CNCF Security Resources

| Resource | Description | Link |
|----------|-------------|------|
| Falco Documentation | Runtime security | [Falco](https://falco.org/docs/) |
| Kyverno Documentation | Policy engine | [Kyverno](https://kyverno.io/docs/) |
| Kubescape Documentation | Compliance scanning | [Kubescape](https://kubescape.io/docs/) |
| Trivy Documentation | Vulnerability scanning | [Trivy](https://trivy.dev/docs/) |
| KubeHound Documentation | Attack graph analysis | [KubeHound](https://kubehound.io/) |

### Industry Standards

| Standard | Relevance | Link |
|----------|-----------|------|
| NIST Cybersecurity Framework | Risk management framework | [NIST CSF](https://www.nist.gov/cyberframework) |
| CIS Kubernetes Benchmark | Configuration hardening | [CIS](https://www.cisecurity.org/benchmark/kubernetes) |
| NSA/CISA Kubernetes Hardening | Government guidance | [NSA/CISA](https://www.nsa.gov/Press-Room/News-Highlights/Article/Article/2716980/nsa-cisa-release-kubernetes-hardening-guidance/) |
| MITRE ATT&CK for Containers | Threat intelligence | [MITRE](https://attack.mitre.org/matrices/enterprise/containers/) |

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | February 2026 | Initial release |

---

*This document is provided for educational purposes as part of the AKS Regulated Enterprise Demo repository. It should not be considered legal or compliance advice. Always consult with your compliance and legal teams when implementing controls for regulated environments.*
