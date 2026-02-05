// KubeHound Identity Attack Queries
// Detect identity-based attack paths in the AKS cluster

// Query 1: Service accounts with secrets access
MATCH (sa:Identity)-[:BOUND_TO]->(rb:RoleBinding)-[:GRANTS]->(r:Role)
WHERE r.rules CONTAINS "secrets"
RETURN sa.name AS service_account,
       sa.namespace AS namespace,
       r.name AS role
ORDER BY sa.namespace;

// Query 2: Containers that can read secrets across namespaces
MATCH path = (c:Container)-[:HAS_IDENTITY]->(sa:Identity)
             -[:BOUND_TO]->(rb:RoleBinding)-[:GRANTS]->(r:Role)
WHERE r.rules CONTAINS "secrets"
  AND r.is_cluster_role = true
RETURN c.name AS container,
       c.namespace AS namespace,
       sa.name AS service_account,
       r.name AS role
ORDER BY c.namespace;

// Query 3: Token theft paths - container to credential access
MATCH path = (c:Container)-[:TOKEN_STEAL|IDENTITY_ASSUME*1..3]->(target:Identity)
WHERE c.namespace = "vulnerable-app"
  AND target.namespace <> c.namespace
RETURN path
LIMIT 15;

// Query 4: Workload identity federation risks
MATCH (sa:Identity)-[:FEDERATED_TO]->(external:ExternalIdentity)
RETURN sa.name AS k8s_service_account,
       sa.namespace AS namespace,
       external.name AS external_identity,
       external.provider AS provider;

// Query 5: Compare vulnerable vs compliant app identity exposure
MATCH (c:Container)-[:HAS_IDENTITY]->(sa:Identity)-[r*1..3]->(target)
WHERE c.namespace IN ["vulnerable-app", "compliant-app"]
RETURN c.namespace AS namespace,
       c.name AS container,
       sa.name AS service_account,
       COUNT(DISTINCT target) AS reachable_targets
ORDER BY reachable_targets DESC;
