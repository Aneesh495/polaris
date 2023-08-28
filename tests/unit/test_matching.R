# Unit Tests: GPS Map Matching, Kalman Filtering, and Viterbi Trellis Decoding

# Test 1: Kalman Filter Noise Reduction & Outlier Flagging
set.seed(123)
n_pts <- 25
true_lats <- seq(37.75, 37.77, length.out = n_pts)
true_lons <- seq(-122.45, -122.43, length.out = n_pts)
timestamps <- seq(0, by = 5, length.out = n_pts)

# Add Gaussian noise (~15 meters std dev)
noisy_lats <- true_lats + rnorm(n_pts, mean = 0, sd = 0.00015)
noisy_lons <- true_lons + rnorm(n_pts, mean = 0, sd = 0.00015)

# Insert an obvious multipath outlier at point 15
noisy_lats[15] <- noisy_lats[15] + 0.005 # ~550m spike

kf_res <- polaris_kalman_filter(noisy_lats, noisy_lons, timestamps, gps_noise_sigma = 5.0)
assert_equal(nrow(kf_res), n_pts, "Kalman filter output rows match input")
assert_true(kf_res$is_outlier[15], "Point 15 must be flagged as innovation outlier")

# Test 2: Emission Probability Monotonicity
e0 <- emission_log_prob_gaussian(0.0, sigma = 4.0)
e5 <- emission_log_prob_gaussian(5.0, sigma = 4.0)
e20 <- emission_log_prob_gaussian(20.0, sigma = 4.0)

assert_true(e0 > e5, "Emission log prob at 0m must be strictly greater than at 5m")
assert_true(e5 > e20, "Emission log prob at 5m must be strictly greater than at 20m")

# Test 3: Transition Probability Discrepancy Penalty
t_exact <- transition_log_prob(route_distance = 100.0, great_circle_distance = 100.0)
t_detour <- transition_log_prob(route_distance = 250.0, great_circle_distance = 100.0)
assert_true(t_exact > t_detour, "Matching route distance has higher transition probability than detour")

# Test 4: End-to-End Viterbi Map Matcher on Known Corridor
# Build a corridor graph: n1 -> n2 -> n3 -> n4
corr_g <- polaris_graph()
corr_g$add_node("n1", 37.750, -122.450)
corr_g$add_node("n2", 37.755, -122.450)
corr_g$add_node("n3", 37.760, -122.450)
corr_g$add_node("n4", 37.765, -122.450)

# Also add an erroneous parallel street 50m to the west: p1 -> p2 -> p3 -> p4
corr_g$add_node("p1", 37.750, -122.451)
corr_g$add_node("p2", 37.755, -122.451)
corr_g$add_node("p3", 37.760, -122.451)
corr_g$add_node("p4", 37.765, -122.451)

corr_g$add_edge("corr_1", "n1", "n2", distance = 555.0, oneway = TRUE)
corr_g$add_edge("corr_2", "n2", "n3", distance = 555.0, oneway = TRUE)
corr_g$add_edge("corr_3", "n3", "n4", distance = 555.0, oneway = TRUE)

corr_g$add_edge("par_1", "p1", "p2", distance = 555.0, oneway = TRUE)
corr_g$add_edge("par_2", "p2", "p3", distance = 555.0, oneway = TRUE)
corr_g$add_edge("par_3", "p3", "p4", distance = 555.0, oneway = TRUE)

corr_g$build_csr()

# Generate noisy GPS trace along corridor n1 -> n2 -> n3 -> n4 with slight eastern bias
trace_df <- data.frame(
  lat = c(37.751, 37.753, 37.757, 37.759, 37.762, 37.764),
  lon = c(-122.4499, -122.4501, -122.4498, -122.4502, -122.4500, -122.4499),
  timestamp = c(10, 20, 30, 40, 50, 60),
  bearing = c(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
)

match_result <- polaris_map_match(corr_g, trace_df, search_radius_meters = 150.0)
assert_equal(match_result$status, "SUCCESS", "Map matching must succeed")
assert_equal(length(match_result$matched_points), 6L, "All 6 pings must be snapped")

# The matched edge sequence must be corr_1 -> corr_2 -> corr_3
assert_true("corr_1" %in% match_result$matched_edges, "corr_1 must be matched")
assert_true("corr_2" %in% match_result$matched_edges, "corr_2 must be matched")
assert_true("corr_3" %in% match_result$matched_edges, "corr_3 must be matched")
assert_true(!("par_1" %in% match_result$matched_edges), "Parallel road must not be matched")
