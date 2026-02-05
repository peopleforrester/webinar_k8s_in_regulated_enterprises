// KubeHound Privilege Escalation Queries
// Detect privilege escalation paths in the AKS cluster

// Query 1: Containers running as privileged
MATCH (c:Container)
WHERE c.privileged = true
RETURN c.name AS container,
       c.namespace AS namespace,
       c.image AS image
ORDER BY c.namespace;

// Query 2: Privilege escalation through hostPID/hostNetwork
MATCH (c:Container)
WHERE c.host_pid = true OR c.host_network = true OR c.host_ipc = true
RETURN c.name AS container,
       c.namespace AS namespace,
       c.host_pid AS hostPID,
       c.host_network AS hostNetwork,
       c.host_ipc AS hostIPC;

// Query 3: Paths from privileged container to node access
MATCH path = (c:Container)-[:CE_PRIV_MOUNT|CE_NSENTER|CE_SYS_PTRACE*1..3]->(n:Node)
WHERE c.namespace = "vulnerable-app"
RETURN path
LIMIT 10;

// Query 4: Service accounts with escalation capabilities
MATCH (sa:Identity)-[:BOUND_TO]->(rb:RoleBinding)-[:GRANTS]->(r:Role)
WHERE r.rules CONTAINS "escalate"
   OR r.rules CONTAINS "bind"
   OR r.rules CONTAINS "impersonate"
RETURN sa.name AS service_account,
       sa.namespace AS namespace,
       r.name AS role,
       r.rules AS dangerous_rules;

// Query 5: Full escalation chain visualization
// Shows: Container -> ServiceAccount -> RoleBinding -> ClusterRole
MATCH path = (c:Container {namespace: "vulnerable-app"})
             -[:HAS_IDENTITY]->(sa:Identity)
             -[:BOUND_TO]->(rb:RoleBinding)
             -[:GRANTS]->(r:Role)
WHERE r.is_cluster_role = true
RETURN path;
