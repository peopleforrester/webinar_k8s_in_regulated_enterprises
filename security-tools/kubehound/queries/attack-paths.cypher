// KubeHound Attack Path Queries
// General attack path discovery for AKS regulated enterprise demo

// Query 1: Find all attack paths from containers to cluster-admin
// Shows how a compromised container could reach cluster-admin privileges
MATCH path = (start:Container)-[*1..6]->(end:Identity)
WHERE end.name = "cluster-admin"
  AND start.namespace IN ["vulnerable-app"]
RETURN path
LIMIT 25;

// Query 2: Find the shortest path from any pod to cluster-admin
MATCH path = shortestPath(
  (start:Container)-[*]->(end:Identity {name: "cluster-admin"})
)
WHERE start.namespace = "vulnerable-app"
RETURN path
LIMIT 10;

// Query 3: Find all containers with excessive permissions
MATCH (c:Container)-[:HAS_IDENTITY]->(sa:Identity)-[:BOUND_TO]->(r:Role)
WHERE r.rules CONTAINS "\"*\""
RETURN c.name AS container,
       sa.name AS service_account,
       r.name AS role,
       c.namespace AS namespace
ORDER BY c.namespace;

// Query 4: Show attack paths through service account tokens
MATCH path = (c:Container)-[:IDENTITY_ASSUME]->(sa:Identity)
              -[:BOUND_TO]->(rb:RoleBinding)-[:GRANTS]->(r:Role)
WHERE r.is_cluster_role = true
  AND c.namespace NOT IN ["kube-system", "kyverno", "falco"]
RETURN path
LIMIT 20;

// Query 5: Count attack paths by severity
MATCH path = (start:Container)-[*1..4]->(end:Identity)
WHERE end.is_cluster_admin = true
RETURN start.namespace AS namespace,
       start.name AS container,
       length(path) AS path_length,
       COUNT(path) AS num_paths
ORDER BY num_paths DESC;
