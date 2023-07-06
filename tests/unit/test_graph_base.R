# Unit Tests: Graph Data Structures, CSR Arrays, and Tarjan SCC

# Test 1: Empty Graph Initialization
g <- polaris_graph()
assert_equal(g$node_count(), 0L, "New graph has 0 nodes")
assert_equal(g$edge_count(), 0L, "New graph has 0 edges")

# Test 2: Add Nodes and Edges
g$add_node("A", lat = 37.77, lon = -122.42)
g$add_node("B", lat = 37.78, lon = -122.41)
g$add_node("C", lat = 37.79, lon = -122.40)
g$add_node("D", lat = 37.80, lon = -122.39)

assert_equal(g$node_count(), 4L, "Graph has 4 nodes")

# Directed edge A -> B
g$add_edge("e1", "A", "B", distance = 1000.0, speed_limit = 50.0, oneway = TRUE)
# Bidirectional edge B <-> C
g$add_edge("e2", "B", "C", distance = 1200.0, speed_limit = 60.0, oneway = FALSE)
# Directed edge C -> D
g$add_edge("e3", "C", "D", distance = 1500.0, speed_limit = 45.0, oneway = TRUE)

assert_equal(g$out_degree("A"), 1L, "Out-degree of A is 1")
assert_equal(g$in_degree("A"), 0L, "In-degree of A is 0")
assert_equal(g$out_degree("B"), 1L, "Out-degree of B is 1 (e2)")
assert_equal(g$in_degree("B"), 2L, "In-degree of B is 2 (e1 and e2_rev)")

# Test 3: Build CSR and check forward/backward arrays
g$build_csr()
assert_true(g$csr_built, "CSR must be marked as built")
assert_equal(length(g$fwd_offsets), 5L, "Forward offsets has length n_nodes + 1")
assert_equal(length(g$bwd_offsets), 5L, "Backward offsets has length n_nodes + 1")

# Test 4: Tarjan Strongly Connected Components
# A -> B <-> C -> D
# B and C form an SCC of size 2; A is size 1; D is size 1
sccs <- g$tarjan_scc()
assert_equal(length(sccs), 3L, "Must identify exactly 3 strongly connected components")
scc_lens <- sort(vapply(sccs, length, integer(1)))
assert_equal(scc_lens, c(1L, 1L, 2L), "Component sizes must be 1, 1, and 2")

# Test 5: Largest SCC extraction
sub_g <- g$largest_scc_subgraph()
assert_equal(sub_g$node_count(), 2L, "Largest SCC subgraph has 2 nodes")
assert_true("B" %in% sub_g$node_ids && "C" %in% sub_g$node_ids, "Nodes B and C are in largest SCC")

# Test 6: Graph Builder from Data Frame
nodes_df <- data.frame(
  id = c("1", "2", "3", "isolated"),
  lat = c(10.0, 10.1, 10.2, 20.0),
  lon = c(20.0, 20.1, 20.2, 30.0)
)
edges_df <- data.frame(
  id = c("e1", "e2"),
  source = c("1", "2"),
  target = c("2", "3"),
  distance = c(500.0, 750.0),
  oneway = c(TRUE, TRUE)
)
g_built <- build_polaris_graph(nodes_df, edges_df, prune_isolated = TRUE)
assert_equal(g_built$node_count(), 3L, "Isolated node must be pruned")
assert_equal(g_built$edge_count(), 2L, "2 edges built")

# Summary check
summ <- graph_summary(g_built)
assert_equal(summ$node_count, 3L)
assert_equal(summ$edge_count, 2L)
assert_equal(summ$total_length_km, 1.25)
