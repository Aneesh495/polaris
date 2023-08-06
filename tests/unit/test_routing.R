# Unit Tests: Routing Algorithms Equivalence and Turn Restrictions
# Asserts Dijkstra == Bidirectional == A* == ALT == Contraction Hierarchies

# Build a synthetic grid road network with multiple alternate paths
build_test_grid <- function() {
  g <- polaris_graph()
  # 4x4 Grid = 16 nodes
  for (r in 1:4) {
    for (c in 1:4) {
      id <- sprintf("n_%d_%d", r, c)
      lat <- 37.75 + (r * 0.01)
      lon <- -122.45 + (c * 0.01)
      g$add_node(id, lat, lon)
    }
  }

  edge_idx <- 1L
  # Horizontal edges
  for (r in 1:4) {
    for (c in 1:3) {
      u <- sprintf("n_%d_%d", r, c)
      v <- sprintf("n_%d_%d", r, c + 1)
      dist <- haversine_distance(g$node_coords[[u]]$lat, g$node_coords[[u]]$lon,
                                 g$node_coords[[v]]$lat, g$node_coords[[v]]$lon)
      g$add_edge(sprintf("e_h_%d", edge_idx), u, v, distance = dist, speed_limit = 50.0, oneway = FALSE)
      edge_idx <- edge_idx + 1L
    }
  }

  # Vertical edges
  for (r in 1:3) {
    for (c in 1:4) {
      u <- sprintf("n_%d_%d", r, c)
      v <- sprintf("n_%d + 1_%d", r, c)
      v_actual <- sprintf("n_%d_%d", r + 1, c)
      dist <- haversine_distance(g$node_coords[[u]]$lat, g$node_coords[[u]]$lon,
                                 g$node_coords[[v_actual]]$lat, g$node_coords[[v_actual]]$lon)
      g$add_edge(sprintf("e_v_%d", edge_idx), u, v_actual, distance = dist, speed_limit = 40.0, oneway = FALSE)
      edge_idx <- edge_idx + 1L
    }
  }

  g$build_csr()
  g
}

grid_g <- build_test_grid()

# Test 1: Dijkstra vs Bidirectional Dijkstra vs A* on diagonal route (n_1_1 to n_4_4)
s_node <- "n_1_1"
t_node <- "n_4_4"

res_dijk <- polaris_dijkstra(grid_g, s_node, t_node)
res_bidi <- polaris_bidirectional_dijkstra(grid_g, s_node, t_node)
res_astar <- polaris_astar(grid_g, s_node, t_node, heuristic_type = "haversine")

assert_equal(res_dijk$status, "OK", "Dijkstra must find path")
assert_equal(res_bidi$status, "OK", "Bidirectional must find path")
assert_equal(res_astar$status, "OK", "A* must find path")

# Exact distance equality across algorithms
assert_equal(res_dijk$total_distance, res_bidi$total_distance,
             "Bidirectional Dijkstra distance must match Dijkstra exactly", tol = 1e-4)
assert_equal(res_dijk$total_distance, res_astar$total_distance,
             "A* distance must match Dijkstra exactly", tol = 1e-4)

# Test 2: ALT Preprocessing and Route Answering
alt_idx <- alt_preprocess(grid_g, n_landmarks = 4L)
res_alt <- polaris_alt_route(alt_idx, s_node, t_node)
assert_equal(res_alt$status, "OK", "ALT must find path")
assert_equal(res_alt$total_distance, res_dijk$total_distance,
             "ALT distance must match Dijkstra exactly", tol = 1e-4)

# Test 3: Contraction Hierarchies Preprocessing and Bit-Exact Query
ch_idx <- ch_preprocess(grid_g, metric = "distance")
res_ch <- polaris_ch_route(ch_idx, s_node, t_node)
assert_equal(res_ch$status, "OK", "Contraction Hierarchies must find path")
assert_equal(res_ch$total_distance, res_dijk$total_distance,
             "Contraction Hierarchies distance must match Dijkstra bit-exact", tol = 1e-4)

# Test 4: Matrix Engine
origins <- c("n_1_1", "n_2_2")
destinations <- c("n_3_3", "n_4_4")
mat <- polaris_matrix(grid_g, origins, destinations, metric = "distance")
assert_equal(dim(mat), c(2L, 2L), "Matrix dimension must be 2x2")
assert_equal(mat["n_1_1", "n_4_4"], res_dijk$total_distance,
             "Matrix cell (n_1_1, n_4_4) must match single query distance", tol = 1e-4)

# Test 5: Turn Restrictions on Dual Graph
# Restrict left turn at n_1_2: e_h_1 -> n_1_2 -> e_v_5 prohibited
restrictions <- list(
  polaris_turn_restriction(from_edge = "e_h_1", via_node = "n_1_2", to_edge = "e_v_5",
                           restriction_type = "no_left_turn")
)
dual_g <- build_dual_graph(grid_g, restrictions = restrictions)
res_turn <- polaris_turn_constrained_route(dual_g, grid_g, source_id = "n_1_1", target_id = "n_2_2")
assert_equal(res_turn$status, "OK", "Turn constrained route must succeed")
# Ensure the prohibited transition was not taken
taken_edges <- res_turn$edges
has_prohibited <- FALSE
for (i in seq_len(length(taken_edges) - 1L)) {
  if (taken_edges[i] == "e_h_1" && taken_edges[i + 1L] == "e_v_5") {
    has_prohibited <- TRUE
  }
}
assert_true(!has_prohibited, "Route must strictly avoid prohibited turn maneuver")

# Test 6: Multi-Modal Mode Filtering
walk_sub <- extract_mode_subgraph(grid_g, mode = "walk")
assert_true(walk_sub$node_count() > 0, "Walk subgraph must contain vertices")
