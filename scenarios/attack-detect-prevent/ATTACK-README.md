# Attack Simulation Scripts

These scripts simulate common attack techniques inside a compromised container.
They are designed to trigger Falco alerts and demonstrate runtime detection.

## Prerequisites

- Vulnerable app deployed: `kubectl apply -f ../../workloads/vulnerable-app/`
- Falco running: `kubectl get pods -n falco`

## Scripts

| Script | MITRE ATT&CK | Falco Rules Triggered |
|--------|--------------|----------------------|
| 01-reconnaissance.sh | T1046, T1083 | Terminal Shell, Service Account Token Read |
| 02-credential-theft.sh | T1552, T1539 | K8s Secrets Access, Database Credential Access |
| 03-lateral-movement.sh | T1021, T1570 | Outbound Connection, Privilege Escalation |

## Usage

```bash
# Run each script from outside the cluster (they kubectl exec into the pod)
./01-reconnaissance.sh
./02-credential-theft.sh
./03-lateral-movement.sh
```

## Monitoring Falco During Attacks

Open a separate terminal to watch Falco alerts:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=1m
```

## Manual Commands

See `attack-commands.md` for individual commands you can run during a live demo.
