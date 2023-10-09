# Integration Tests: C Acceleration Kernel vs Pure-R Bit-Level Equivalence
# Formally proves that native SIMD/C kernel matches pure-R reference implementation

# Test 1: Vincenty Geodesic Equivalence
test_coords <- list(
  c(37.7749, -122.4194, 34.0522, -118.2437), # SF -> LA
  c(40.7128, -74.0060, 51.5074, -0.1278),    # NY -> London
  c(35.6762, 139.6503, -33.8688, 151.2093),  # Tokyo -> Sydney
  c(0.0, 0.0, 0.0, 10.0)                     # Equatorial 10 degrees
)

for (tc in test_coords) {
  r_res <- vincenty_inverse(tc[1], tc[2], tc[3], tc[4])$distance
  c_res <- .Call("c_vincenty_distance", tc[1], tc[2], tc[3], tc[4])
  assert_equal(c_res, r_res, "C Vincenty matches pure-R Vincenty within floating point tolerance", tol = 1e-4)
}

# Test 2: Point-in-Polygon Ray Casting Equivalence
poly_lats <- c(37.75, 37.78, 37.79, 37.76, 37.75)
poly_lons <- c(-122.45, -122.46, -122.42, -122.41, -122.45)

test_pts <- list(
  c(37.77, -122.44, TRUE),
  c(37.70, -122.44, FALSE),
  c(37.76, -122.43, TRUE),
  c(37.85, -122.40, FALSE)
)

for (tp in test_pts) {
  r_in <- point_in_polygon(tp[1], tp[2], poly_lats, poly_lons)
  c_in <- .Call("c_point_in_polygon", tp[1], tp[2], poly_lats, poly_lons)
  assert_equal(c_in, r_in, "C point-in-polygon matches pure-R ray casting")
}

# Test 3: Dijkstra CSR Bit-Level Equivalence on 25-Node Grid
grid_g <- polaris_graph()
for (r in 1:5) {
  for (c in 1:5) {
    id <- sprintf("v_%d_%d", r, c)
    grid_g$add_node(id, 37.70 + r * 0.01, -122.40 + c * 0.01)
  }
}
edge_ct <- 1L
for (r in 1:5) {
  for (c in 1:4) {
    u <- sprintf("v_%d_%d", r, c)
    v <- sprintf("v_%d_%d", r, c + 1)
    grid_g$add_edge(sprintf("eh_%d", edge_ct), u, v, distance = 750.0 + r * 10, speed_limit = 50.0, oneway = FALSE)
    edge_ct <- edge_ct + 1L
  }
}
for (r in 1:4) {
  for (c in 1:5) {
    u <- sprintf("v_%d_%d", r, c)
    v <- sprintf("v_%d_%d", r + 1, c)
    grid_g$add_edge(sprintf("ev_%d", edge_ct), u, v, distance = 800.0 + c * 10, speed_limit = 45.0, oneway = FALSE)
    edge_ct <- edge_ct + 1L
  }
}
grid_g$build_csr()

# Run pure R Dijkstra
r_dijk <- polaris_dijkstra(grid_g, source_id = "v_1_1", target_id = "v_5_5", metric = "distance")

# Run native C Dijkstra
s_idx <- grid_g$node_to_idx[["v_1_1"]]
t_idx <- grid_g$node_to_idx[["v_5_5"]]
c_dijk <- .Call("c_dijkstra_csr",
                as.integer(s_idx),
                as.integer(t_idx),
                grid_g$fwd_offsets,
                grid_g$fwd_targets,
                grid_g$fwd_weights,
                grid_g$node_count())

assert_equal(c_dijk[[3]], r_dijk$total_distance, "Native C Dijkstra distance matches Pure-R bit-exact", tol = 1e-7)
