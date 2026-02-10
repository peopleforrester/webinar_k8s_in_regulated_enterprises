# Falco Talon - Automated Threat Response

Falco Talon is the official response engine for Falco, providing automated
threat response capabilities for Kubernetes environments.

## Version

- **Talon Version**: 0.3.0
- **Falco Version**: 0.43.0 (required)

## Overview

Falco Talon connects to Falco's gRPC output and executes automated response
actions based on configurable rules. This enables:

- **Immediate containment**: Isolate compromised pods with network policies
- **Evidence preservation**: Label pods for forensic investigation
- **Threat termination**: Kill pods exhibiting malicious behavior
- **Audit trail**: Log all automated actions for compliance

## Response Actions

| Action | Description | Use Case |
|--------|-------------|----------|
| `kubernetes:networkpolicy` | Create/modify NetworkPolicy | Isolate compromised pods |
| `kubernetes:label` | Add labels to pods | Mark for investigation |
| `kubernetes:terminate` | Delete pod | Stop active threats |
| `kubernetes:script` | Run script in pod | Capture forensics |

## Installation

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco-talon falcosecurity/falco-talon \
  -n falco \
  -f values.yaml
```

## Response Rules

See `response-rules.yaml` for the configured automated responses:

1. **Crypto Mining** → Network isolation + forensic capture
2. **Privilege Escalation** → Immediate termination
3. **Credential Access** → Label for investigation
4. **Data Exfiltration** → Block egress traffic

## Regulatory Alignment

Automated response capabilities address:

- **DORA Article 17**: ICT incident management requires immediate response
- **NCUA**: Supervisory expectations for automated security controls
- **PCI-DSS 4.0.1**: Real-time detection and response requirements

## Demo Integration

During the demo, Falco Talon demonstrates the "Respond" capability:

1. Falco detects malicious activity (e.g., crypto mining)
2. Talon receives the alert via gRPC
3. Talon automatically isolates the pod with a NetworkPolicy
4. Security team is notified via webhook

This transforms detection from "alert and wait" to "detect and contain."
