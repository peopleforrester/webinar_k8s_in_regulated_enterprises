# AKS Regulated Enterprise - Anki Flashcards

Import these into Anki using the "Basic" note type.
Format: Front // Back (separated by //)

---

## SECTION 1: CNCF Security Tools (Cards 1-15)

### Card 1
**[Falco] What is Falco and what CNCF status does it have?**
//
**Falco** is a runtime security tool that detects threats in containers and Kubernetes.

**CNCF Status:** Graduated (highest maturity level)

**Key capability:** Uses eBPF/syscall monitoring to detect malicious behavior in real-time.

```yaml
# Falco detects this attack:
kubectl exec -it pod -- cat /etc/shadow
# Alert: "Read sensitive file below /etc"
```

---

### Card 2
**[Falco] What is the difference between legacy eBPF and modern_ebpf drivers in Falco 0.43.0?**
//
**modern_ebpf** (recommended):
- Uses CO-RE (Compile Once, Run Everywhere)
- No kernel headers needed
- Better performance

**legacy eBPF** (deprecated in 0.43.0):
- Requires kernel headers
- Slower compilation
- Being removed

```yaml
# values.yaml
driver:
  kind: modern_ebpf  # Use this in 2026
```

---

### Card 3
**[Falco Talon] What is Falco Talon and how does it extend Falco?**
//
**Falco Talon** is the official response engine for Falco.

**Purpose:** Automates threat response when Falco detects an attack.

**Actions:**
- `kubernetes:networkpolicy` - Isolate pod
- `kubernetes:label` - Mark for investigation
- `kubernetes:terminate` - Kill pod

```yaml
# Auto-isolate crypto miners
- name: isolate-cryptominer
  match:
    rules: ["Detect Crypto Mining Process"]
  action:
    name: kubernetes:networkpolicy
```

---

### Card 4
**[Kyverno] What is Kyverno and why is it preferred over OPA/Gatekeeper?**
//
**Kyverno** is a Kubernetes-native policy engine.

**CNCF Status:** Incubating

**Why preferred:**
- YAML-native (no Rego language)
- Validates, mutates, and generates resources
- Easy for Kubernetes teams to adopt

```yaml
# Simple policy - no Rego required
spec:
  rules:
    - name: deny-privileged
      validate:
        pattern:
          spec:
            containers:
              - securityContext:
                  privileged: false
```

---

### Card 5
**[Kyverno] What is ValidatingAdmissionPolicy (VAP) and why enable it in Kyverno 1.17.0?**
//
**VAP** executes policies at the API server level (not webhooks).

**Benefits:**
- Lower latency (no webhook round-trip)
- More reliable (built into API server)
- Better performance at scale

```yaml
# Enable in values.yaml
autogen:
  validatingAdmissionPolicy:
    enabled: true
```

**Note:** Kyverno auto-generates VAP from ClusterPolicies.

---

### Card 6
**[Kubescape] What frameworks does Kubescape scan against?**
//
**Kubescape** scans for compliance against multiple frameworks:

| Framework | Purpose |
|-----------|---------|
| **NSA/CISA** | US government hardening guide |
| **CIS-v1.12.0** | Industry security benchmark |
| **MITRE ATT&CK** | Threat detection mapping |
| **SOC 2** | Service organization controls |

```bash
# Run multi-framework scan
kubescape scan framework nsa,cis-v1.12.0,soc2
```

**CNCF Status:** Incubating (as of Jan 2025)

---

### Card 7
**[Kubescape] What version of CIS Kubernetes Benchmark should you use with K8s 1.34?**
//
**CIS-v1.12.0** (released 2026)

**Why:** Aligns with Kubernetes 1.30-1.34 and includes:
- Updated cryptographic standards
- New PSS (Pod Security Standards) checks
- AppArmor GA requirements

```yaml
# kubescape values.yaml
scanner:
  frameworks:
    - CIS-v1.12.0  # Not "CIS-Kubernetes" (outdated)
```

---

### Card 8
**[Trivy] What types of scanning does Trivy Operator perform?**
//
**Trivy Operator** provides 4 scan types:

1. **Vulnerability scanning** - CVEs in images
2. **SBOM generation** - Software Bill of Materials
3. **Config audit** - Kubernetes misconfigurations
4. **Secret scanning** - Leaked credentials

```yaml
# values.yaml
vulnerabilityReportsScanner: Trivy
configAuditScannerEnabled: true
exposedSecretScannerEnabled: true
sbomGeneration:
  enabled: true
```

---

### Card 9
**[Trivy] What SBOM formats does Trivy support and why do regulations require them?**
//
**Formats:** CycloneDX and SPDX

**Regulatory requirement:** Supply chain transparency

| Regulation | SBOM Requirement |
|------------|------------------|
| DORA Article 28 | Third-party component inventory |
| OSFI B-10 | Third-party risk visibility |
| US Executive Order 14028 | Federal software supply chain |

```bash
trivy image --format cyclonedx nginx:1.25
```

---

### Card 10
**[KubeHound] What is KubeHound and who maintains it?**
//
**KubeHound** maps Kubernetes attack paths using graph analysis.

**Maintainer:** Datadog's Adversary Simulation Engineering team

**Version:** 1.6.7 (Feb 2026)

**Key feature:** MITRE ATT&CK framework binding

```cypher
// Find paths from compromised pod to cluster-admin
MATCH path = (start:Pod)-[*1..5]->(end:Role)
WHERE end.name = "cluster-admin"
RETURN path
```

---

### Card 11
**[KubeHound] What attack path would KubeHound find if a pod can read secrets?**
//
**Attack path:** Pod → ServiceAccount → Secret Access → Credential Theft → Lateral Movement

**MITRE ATT&CK:** T1552.007 (Container API Credentials)

```cypher
// Query for secret access paths
MATCH (p:Pod)-[:USES]->(sa:ServiceAccount)
       -[:HAS_PERMISSION]->(r:Role)
WHERE r.rules CONTAINS "secrets"
RETURN p.name, sa.name, r.rules
```

**Mitigation:** Kyverno policy to block secrets access in RBAC.

---

### Card 12
**[AKS] Why did Azure replace Azure NPM with Cilium in 2026?**
//
**Azure NPM is retiring:**
- Windows: September 2026
- Linux: September 2028

**Cilium advantages:**
- eBPF-based (faster, more efficient)
- L7 network policies (HTTP, gRPC)
- No 250-node/20,000-pod limit

```hcl
# Terraform
network_profile {
  network_plugin      = "azure"
  network_plugin_mode = "overlay"
  network_data_plane  = "cilium"
}
```

---

### Card 13
**[AKS] What is AKS Image Cleaner and why enable it?**
//
**Image Cleaner** automatically removes unused/vulnerable images from nodes.

**Based on:** Eraser open-source project

**Uses:** Trivy for vulnerability detection

```hcl
# Terraform
image_cleaner_enabled        = true
image_cleaner_interval_hours = 168  # Weekly
```

**Why:** Reduces attack surface, frees disk space, compliance requirement.

---

### Card 14
**[AKS] Why use AzureLinux instead of Ubuntu for AKS nodes?**
//
**Azure Linux 2.0 was retired November 2025.**

**AzureLinux (Mariner) benefits:**
- Smaller attack surface
- Faster security patching
- FIPS 140-2 support
- CIS benchmark aligned

```hcl
default_node_pool {
  os_sku = "AzureLinux"  # Not "Ubuntu"
}
```

---

### Card 15
**[AKS] What Kubernetes version should regulated enterprises use in 2026?**
//
**Kubernetes 1.34** (GA November 2025)

**Why 1.34:**
- Latest stable GA version
- LTS-eligible with Premium tier
- AppArmor GA included
- Sidecar Containers GA

**Avoid:** 1.29 (EOL March 2025), 1.35 (Preview only)

```hcl
variable "kubernetes_version" {
  default = "1.34"
}
```

---

## SECTION 2: US Regulations (Cards 16-25)

### Card 16
**[NCUA] What is NCUA and what institutions does it regulate?**
//
**NCUA** = National Credit Union Administration

**Regulates:** Federally insured credit unions in the United States

**Key documents:**
- 12 CFR Part 748 (Security Program)
- Supervisory Priorities (annual)
- ACET (Automated Cybersecurity Examination Tool)

**Demo relevance:** Kyverno policies address least privilege requirements.

---

### Card 17
**[NCUA] What does 12 CFR Part 748 require for access controls?**
//
**12 CFR 748 Appendix A** requires:
- Least privilege access
- Separation of duties
- Access review procedures
- Audit logging

**Demo mapping:**
| Requirement | Tool |
|-------------|------|
| Least privilege | Kyverno `require-run-as-nonroot` |
| Audit logging | Falco runtime detection |
| Access review | Kubescape compliance scans |

---

### Card 18
**[NCUA] What is ACET and how does it relate to Kubescape?**
//
**ACET** = Automated Cybersecurity Examination Tool

**Purpose:** Credit union self-assessment against NCUA cybersecurity expectations.

**Kubescape mapping:**
- Domain 1: Cyber Risk Management → NSA framework
- Domain 2: Threat Intelligence → MITRE ATT&CK
- Domain 4: Cybersecurity Controls → CIS-v1.12.0

```bash
kubescape scan framework nsa,mitre --submit
```

---

### Card 19
**[FFIEC] What is FFIEC and which agencies comprise it?**
//
**FFIEC** = Federal Financial Institutions Examination Council

**Member agencies:**
- OCC (Comptroller of Currency)
- FDIC
- Federal Reserve
- NCUA
- CFPB

**Key guidance:** IT Examination Handbook, Cloud Computing Statement

---

### Card 20
**[FFIEC] What does FFIEC say about container security in regulated environments?**
//
**FFIEC IT Handbook** (Information Security booklet) requires:

- Configuration management (Kyverno policies)
- Vulnerability management (Trivy scanning)
- Continuous monitoring (Falco detection)
- Change control (image digest pinning)

```yaml
# Addresses FFIEC IS-II.C.5
image: nginx@sha256:abc123...  # Digest, not tag
```

---

### Card 21
**[FFIEC] What is the FFIEC Cloud Computing guidance requirement for third-party risk?**
//
**FFIEC Cloud Statement** (2020, updated 2023) requires:

- Due diligence on cloud providers
- Contractual protections
- Ongoing monitoring
- Exit strategy

**Demo mapping:**
| Requirement | Tool |
|-------------|------|
| Component inventory | Trivy SBOM |
| Vulnerability monitoring | Trivy + Kubescape |
| Configuration drift | Kyverno background scans |

---

### Card 22
**[US] What is the incident reporting timeline for US financial institutions?**
//
**72 hours** for significant incidents

**Sources:**
- NCUA: 12 CFR 748.1(c)
- OCC/FDIC/Fed: 36-hour notification rule (2022)

**Contrast with DORA:** EU requires **4 hours** for major ICT incidents.

**Demo relevance:** Falco + Falcosidekick enables fast incident detection and notification.

---

### Card 23
**[US] What is the difference between NCUA and FFIEC guidance?**
//
| Aspect | NCUA | FFIEC |
|--------|------|-------|
| **Scope** | Credit unions only | All federal FIs |
| **Authority** | Regulatory (binding) | Guidance (exam standards) |
| **Documents** | 12 CFR Part 748 | IT Examination Handbook |
| **Exams** | NCUA examiners | Agency-specific |

**Both require:** Least privilege, monitoring, vulnerability management.

---

### Card 24
**[US] What logging requirements apply to Kubernetes in regulated US environments?**
//
**Requirements:**
- Audit trail for all privileged actions
- Log retention (varies: 1-7 years)
- Tamper-proof storage
- Access logging

**Demo implementation:**
```yaml
# Falco detects and logs
- rule: Terminal Shell in Container
  output: "Shell spawned (user=%user.name pod=%k8s.pod.name)"
  priority: WARNING
```

---

### Card 25
**[US] How does the NIST Cybersecurity Framework 2.0 relate to container security?**
//
**NIST CSF 2.0** (Feb 2024) added **Govern** function:

| Function | Container Control |
|----------|-------------------|
| **Govern** | Policy-as-code (Kyverno) |
| **Identify** | Attack paths (KubeHound) |
| **Protect** | Admission control (Kyverno) |
| **Detect** | Runtime monitoring (Falco) |
| **Respond** | Automated response (Talon) |
| **Recover** | Image cleanup (Image Cleaner) |

---

## SECTION 3: Canadian Regulations (Cards 26-35)

### Card 26
**[OSFI] What is OSFI and what institutions does it regulate?**
//
**OSFI** = Office of the Superintendent of Financial Institutions

**Regulates:** Canadian FRFIs (Federally Regulated Financial Institutions):
- Banks
- Insurance companies
- Trust and loan companies
- Pension plans

**Key guidelines:** B-10, B-13, E-21, E-23

---

### Card 27
**[OSFI B-10] What does OSFI B-10 require for third-party risk management?**
//
**OSFI B-10** (effective May 2024): Third-Party Risk Management

**Requirements:**
- Third-party inventory (including open-source)
- Due diligence before use
- Ongoing monitoring
- Exit strategies

**Demo mapping:**
| Requirement | Tool |
|-------------|------|
| Component inventory | Trivy SBOM |
| Vulnerability monitoring | Trivy scanning |
| Supply chain integrity | Kyverno `require-image-digest` |

---

### Card 28
**[OSFI B-13] What are the five domains of OSFI B-13?**
//
**OSFI B-13** (effective Jan 2024): Technology and Cyber Risk

**Five domains:**
1. **Governance** - Board oversight
2. **Technology Operations** - Availability, capacity
3. **Cyber Security** - Controls, monitoring
4. **Technology Resilience** - DR, BCP
5. **Third-Party** - Vendor management

**All map to demo tools** (Falco, Kyverno, Kubescape, Trivy).

---

### Card 29
**[OSFI B-13] What does OSFI B-13 Section 4.3 require for access controls?**
//
**B-13 Section 4.3** requires:
- Least privilege access
- Privilege access management
- Regular access reviews
- Segregation of duties

**Demo mapping:**
```yaml
# Kyverno policy addresses B-13 4.3
metadata:
  annotations:
    compliance.regulated/osfi-b13: "Section 4.3 - Access Controls"
spec:
  rules:
    - name: require-run-as-nonroot
```

---

### Card 30
**[OSFI B-13] What vulnerability remediation SLAs does OSFI B-13 expect?**
//
**B-13 Section 5.1** - Expected remediation timelines:

| Severity | Timeline |
|----------|----------|
| Critical | 24-72 hours |
| High | 7-14 days |
| Medium | 30-60 days |
| Low | 90 days |

**Demo:** Trivy scanning identifies vulnerabilities with severity for prioritization.

---

### Card 31
**[OSFI E-21] What is OSFI E-21 and when does it take effect?**
//
**OSFI E-21** = Operational Risk Management

**Effective:** July 1, 2025

**Key principles:**
- Three lines of defense model
- Risk identification and assessment
- Operational resilience
- Incident management

**Demo mapping:**
| Line of Defense | Tool |
|-----------------|------|
| 1st (Prevention) | Kyverno |
| 2nd (Monitoring) | Falco |
| 3rd (Assurance) | Kubescape |

---

### Card 32
**[OSFI E-23] What does OSFI E-23 require for AI governance?**
//
**OSFI E-23** (AI provisions effective May 2027): Model Risk Management

**AI requirements:**
- Model inventory (including AI/ML)
- Validation and testing
- Explainability requirements
- Human oversight

**Demo relevance:** AI-powered security tools (Falco ML features) must be inventoried and validated.

---

### Card 33
**[Canada] How does Canadian data residency affect AKS deployments?**
//
**Canadian FRFIs** often require data to stay in Canada.

**Azure regions:**
- Canada Central (Toronto)
- Canada East (Quebec City)

```hcl
variable "location" {
  default = "canadacentral"  # For OSFI compliance
}
```

**Note:** Some workloads may use US regions with OSFI approval.

---

### Card 34
**[Canada] What is the difference between OSFI B-10 and B-13?**
//
| Aspect | B-10 | B-13 |
|--------|------|------|
| **Focus** | Third-party risk | Technology/cyber risk |
| **Scope** | Vendors, outsourcing | IT systems, security |
| **Effective** | May 2024 | January 2024 |

**Both apply to containers:**
- B-10: Open-source components, cloud providers
- B-13: Container security, vulnerability management

---

### Card 35
**[Canada] What OSFI guideline covers operational resilience for Kubernetes?**
//
**OSFI E-21** (Operational Risk Management) - effective July 2025

**Kubernetes relevance:**
- Pod disruption budgets
- Multi-AZ deployments
- Disaster recovery
- Capacity management

**Demo mapping:**
```yaml
# Kyverno require-resource-limits addresses E-21
# Prevents resource exhaustion attacks
resources:
  limits:
    cpu: "500m"
    memory: "256Mi"
```

---

## SECTION 4: EU Regulations (Cards 36-45)

### Card 36
**[DORA] What is DORA and when did it become effective?**
//
**DORA** = Digital Operational Resilience Act

**Effective:** January 17, 2025 (NO transitional period)

**Scope:** EU financial entities including:
- Banks
- Investment firms
- Insurance companies
- Payment providers

**Key requirement:** 4-hour incident reporting (vs US 72-hour).

---

### Card 37
**[DORA] What are the five pillars of DORA?**
//
**DORA's Five Pillars:**

1. **ICT Risk Management** (Articles 5-16)
2. **ICT Incident Reporting** (Articles 17-23)
3. **Digital Resilience Testing** (Articles 24-27)
4. **ICT Third-Party Risk** (Articles 28-44)
5. **Information Sharing** (Article 45)

**Demo covers:** Pillars 1, 2, and 4 primarily.

---

### Card 38
**[DORA] What does DORA Article 9 require for ICT systems?**
//
**Article 9: Protection and Prevention**

**Requirements:**
- Access control policies
- Authentication mechanisms
- Vulnerability management
- Patch management
- Network security

**Demo mapping:**
| Article 9 Section | Tool |
|-------------------|------|
| 9(4)(c) Access control | Kyverno |
| 9(4)(d) Vulnerability mgmt | Trivy |
| 9(4)(e) Change management | `require-image-digest` |

---

### Card 39
**[DORA] What is DORA's incident reporting timeline?**
//
**DORA Article 19:** Major ICT incidents must be reported within **4 hours**.

**Reporting phases:**
1. **Initial notification:** 4 hours
2. **Intermediate report:** 72 hours
3. **Final report:** 1 month

**Contrast with US:** 72 hours initial notification

**Demo:** Falco + Falcosidekick enables real-time detection for rapid reporting.

---

### Card 40
**[DORA] What does DORA Article 28 require for third-party ICT providers?**
//
**Article 28: Third-Party ICT Risk**

**Requirements:**
- Register of ICT third-party providers
- Risk assessment before use
- Contractual provisions
- Exit strategies

**Demo mapping:**
| Requirement | Tool |
|-------------|------|
| Component registry | Trivy SBOM |
| Continuous monitoring | Kubescape |
| Supply chain integrity | Kyverno image policies |

---

### Card 41
**[DORA] How does DORA affect Azure/Microsoft as a third-party provider?**
//
**DORA Critical Third-Party Provider (CTPP)** designation:

- ESAs may designate cloud providers as CTTPs
- Microsoft Azure may be designated
- Direct regulatory oversight possible
- Additional contractual requirements

**Impact on demo:** Financial entities must document Azure as third-party per Article 28.

---

### Card 42
**[EU AI Act] What is the EU AI Act and when does it take effect?**
//
**EU AI Act:** First comprehensive AI regulation globally.

**Timeline:**
- Unacceptable risk AI: Feb 2025
- High-risk AI: **August 2, 2026**
- General provisions: Aug 2027

**Relevance:** AI-powered security tools (anomaly detection, ML-based Falco rules) may be in scope.

---

### Card 43
**[EU AI Act] What are the four risk levels in the EU AI Act?**
//
**EU AI Act Risk Classification:**

| Level | Example | Requirement |
|-------|---------|-------------|
| **Unacceptable** | Social scoring | Banned |
| **High-Risk** | Credit scoring AI | Full compliance |
| **Limited** | Chatbots | Transparency |
| **Minimal** | Spam filters | None |

**Security AI:** May be high-risk if used for credit/fraud decisions.

---

### Card 44
**[EU] How do DORA and EU AI Act overlap for AI-powered security?**
//
**Overlap areas:**

| Aspect | DORA | EU AI Act |
|--------|------|-----------|
| **Scope** | ICT systems | AI systems |
| **Governance** | ICT risk framework | AI risk assessment |
| **Monitoring** | Continuous | Ongoing |
| **Documentation** | Incident logs | Technical documentation |

**Demo:** AI-powered Falco rules subject to both.

---

### Card 45
**[EU] What is the timeline difference between EU and US incident reporting?**
//
**Incident Reporting Comparison:**

| Jurisdiction | Initial Report | Source |
|--------------|----------------|--------|
| **EU (DORA)** | **4 hours** | Article 19 |
| **US (OCC/Fed)** | 36 hours | 2022 Rule |
| **US (NCUA)** | 72 hours | 12 CFR 748 |

**Implication:** If you operate in EU, your SLA is 4 hours for all markets.

---

## SECTION 5: Security Concepts (Cards 46-55)

### Card 46
**[Security] What is the principle of least privilege in Kubernetes?**
//
**Least Privilege:** Grant only minimum permissions needed.

**Kubernetes implementation:**
1. `runAsNonRoot: true` - No root in containers
2. `allowPrivilegeEscalation: false` - No privilege gain
3. `readOnlyRootFilesystem: true` - No file writes
4. Drop all capabilities

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

---

### Card 47
**[Security] What is container escape and how do policies prevent it?**
//
**Container Escape:** Breaking out of container to access host.

**Attack vectors:**
- Privileged containers
- Host path mounts
- Kernel exploits from root

**Prevention (Kyverno):**
```yaml
# Block privileged containers
validate:
  pattern:
    spec:
      containers:
        - securityContext:
            privileged: false
```

---

### Card 48
**[Security] What is the difference between Enforce and Audit modes in Kyverno?**
//
| Mode | Behavior |
|------|----------|
| **Enforce** | Blocks non-compliant resources |
| **Audit** | Allows but reports violations |

**When to use:**
- **Enforce:** Critical policies (no privileged)
- **Audit:** Aspirational policies (image digests)

```yaml
spec:
  validationFailureAction: Enforce  # or Audit
```

---

### Card 49
**[Security] What is a Software Bill of Materials (SBOM) and why is it required?**
//
**SBOM:** Inventory of all software components in an application.

**Why required:**
- Supply chain transparency (DORA, B-10)
- Vulnerability tracking
- License compliance
- Incident response

**Formats:** CycloneDX, SPDX

```bash
# Generate SBOM with Trivy
trivy image --format spdx-json nginx:1.25
```

---

### Card 50
**[Security] What MITRE ATT&CK technique is credential theft from pods?**
//
**T1552.007:** Unsecured Credentials: Container API

**Attack:** Reading service account tokens from pods.

**Path:** `/var/run/secrets/kubernetes.io/serviceaccount/token`

**Detection (Falco):**
```yaml
- rule: Read Service Account Token
  condition: >
    open_read and container and
    fd.name startswith "/var/run/secrets/kubernetes.io"
  priority: WARNING
  tags: [mitre-t1552.007]
```

---

### Card 51
**[Security] What is the difference between runtime detection and admission control?**
//
| Aspect | Admission Control | Runtime Detection |
|--------|-------------------|-------------------|
| **When** | Before deployment | After running |
| **Tool** | Kyverno | Falco |
| **Action** | Block/Mutate | Alert/Respond |
| **Scope** | Kubernetes API | Syscalls/behavior |

**Together:** Defense in depth - block bad configs, detect bad behavior.

---

### Card 52
**[Security] What is the seccomp profile and why use RuntimeDefault?**
//
**Seccomp:** Restricts syscalls a container can make.

**RuntimeDefault:** Container runtime's default filter (blocks ~50+ dangerous syscalls).

```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault
```

**Why:** Reduces kernel attack surface. Required by CIS benchmarks.

---

### Card 53
**[Security] Why should you pin images by digest instead of tag?**
//
**Tags are mutable.** `nginx:1.25` can point to different images over time.

**Digests are immutable.** SHA256 hash of exact image.

```yaml
# Bad - tag can change
image: nginx:1.25

# Good - digest is immutable
image: nginx@sha256:abc123...
```

**Regulatory:** DORA Article 9(4)(e), OSFI B-13 Section 5.2

---

### Card 54
**[Security] What is the defense-in-depth approach in this demo?**
//
**Four layers of defense:**

| Layer | Tool | Function |
|-------|------|----------|
| **1. Visibility** | KubeHound | Attack path analysis |
| **2. Detection** | Falco | Runtime monitoring |
| **3. Prevention** | Kyverno | Policy enforcement |
| **4. Compliance** | Kubescape | Posture management |

**Plus:** Falco Talon for automated response, Trivy for vulnerability scanning.

---

### Card 55
**[Security] What is the Attack → Detect → Prevent → Prove narrative?**
//
**Demo narrative arc:**

1. **Attack (SEE):** KubeHound shows attack paths
2. **Detect:** Falco alerts on malicious activity
3. **Prevent:** Kyverno blocks policy violations
4. **Prove:** Kubescape shows compliance improvement

**Compliance scores:**
- Before: 67%
- After: 94%

---

## SECTION 6: Demo Specifics (Cards 56-60)

### Card 56
**[Demo] What are the six Kyverno policies in the demo and their modes?**
//
**Enforce mode (4):**
1. `disallow-privileged-containers`
2. `disallow-latest-tag`
3. `require-run-as-nonroot`
4. `require-resource-limits`

**Audit mode (2):**
5. `require-image-digest`
6. `require-readonly-rootfs`

**Why Audit?** Image digests and read-only rootfs need tooling maturity first.

---

### Card 57
**[Demo] What security violations does the vulnerable-app demonstrate?**
//
**Six violations:**

1. `:latest` image tag
2. No resource limits
3. Privileged: true
4. Runs as root
5. Writable filesystem
6. Service account token mounted

```yaml
# All of these are wrong:
securityContext:
  privileged: true
  runAsUser: 0
```

**Each blocked by a Kyverno policy.**

---

### Card 58
**[Demo] What security controls does the compliant-app implement?**
//
**Ten controls:**

1. Pinned image version (`nginx:1.25.4`)
2. Resource limits
3. Non-privileged
4. runAsNonRoot: true (UID 101)
5. Read-only root filesystem
6. No privilege escalation
7. All capabilities dropped
8. Seccomp: RuntimeDefault
9. NetworkPolicy (ingress/egress)
10. Token mount disabled

---

### Card 59
**[Demo] What tools are needed to run this demo?**
//
**Prerequisites:**

| Tool | Version | Purpose |
|------|---------|---------|
| Azure CLI | 2.50+ | Azure authentication |
| Terraform | 1.5+ | Infrastructure |
| kubectl | 1.30+ | Cluster access |
| Helm | 3.14+ | Tool installation |
| Docker | 24+ | KubeHound |

```bash
./scripts/setup-cluster.sh  # Deploys AKS
./scripts/install-tools.sh  # Installs tools
```

---

### Card 60
**[Demo] What is the total deployment time for the demo environment?**
//
**Deployment timeline:**

| Phase | Duration |
|-------|----------|
| AKS cluster (Terraform) | 8-12 minutes |
| Security tools (Helm) | 3-5 minutes |
| Demo workloads (kubectl) | 1 minute |
| **Total** | **~15 minutes** |

**Tip:** Deploy 30 minutes before demo. Run `TESTING-CHECKLIST.md` first.

---

## Import Instructions

To import into Anki:
1. Copy each card's content
2. Use `//` as the separator between front and back
3. Import as "Basic" note type
4. Or use Anki's "Import" feature with custom delimiter

Alternatively, use an Anki add-on that supports Markdown import.
