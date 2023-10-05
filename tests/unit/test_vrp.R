# Unit Tests: Vehicle Routing Problem (CVRP and VRPTW)

# Create small distribution cluster in SF
depot <- polaris_vrp_depot("DEPOT", lat = 37.7749, lon = -122.4194)

# 6 customers
customers <- list(
  polaris_vrp_customer("C1", lat = 37.778, lon = -122.415, demand = 20.0, ready_time = 28800, due_time = 36000),
  polaris_vrp_customer("C2", lat = 37.780, lon = -122.410, demand = 30.0, ready_time = 28800, due_time = 36000),
  polaris_vrp_customer("C3", lat = 37.785, lon = -122.405, demand = 25.0, ready_time = 28800, due_time = 36000),
  polaris_vrp_customer("C4", lat = 37.765, lon = -122.430, demand = 35.0, ready_time = 28800, due_time = 36000),
  polaris_vrp_customer("C5", lat = 37.760, lon = -122.435, demand = 15.0, ready_time = 28800, due_time = 36000),
  polaris_vrp_customer("C6", lat = 37.755, lon = -122.440, demand = 20.0, ready_time = 28800, due_time = 36000)
)

# Vehicle capacity = 80 units
# Cluster 1 (C1, C2, C3) total demand = 75 <= 80 (fits in 1 vehicle)
# Cluster 2 (C4, C5, C6) total demand = 70 <= 80 (fits in 1 vehicle)
problem <- polaris_vrp_problem(depot, customers, vehicle_capacity = 80.0, num_vehicles = 3L)

# Test 1: Clarke-Wright Savings
cw_routes <- clarke_wright_savings(problem)
assert_equal(length(cw_routes), 2L, "Clarke-Wright must group 6 customers into exactly 2 routes")

for (r in cw_routes) {
  assert_true(r$load <= 80.0, "Every route must satisfy capacity <= 80")
  assert_equal(r$stops[1], "DEPOT", "Route starts at depot")
  assert_equal(r$stops[length(r$stops)], "DEPOT", "Route ends at depot")
}

# Test 2: 2-Opt Tour Untangling
# Artificially cross a tour
crossed_tour <- c("C1", "C3", "C2")
untangled <- two_opt_tour(crossed_tour, "DEPOT", problem$distance_matrix)
d_crossed <- problem$distance_matrix["DEPOT", "C1"] + problem$distance_matrix["C1", "C3"] +
             problem$distance_matrix["C3", "C2"] + problem$distance_matrix["C2", "DEPOT"]
d_untangled <- problem$distance_matrix["DEPOT", untangled[1]] + problem$distance_matrix[untangled[1], untangled[2]] +
               problem$distance_matrix[untangled[2], untangled[3]] + problem$distance_matrix[untangled[3], "DEPOT"]
assert_true(d_untangled <= d_crossed, "2-opt must not increase tour length")

# Test 3: Tabu Search Fleet Optimization
tabu_sol <- polaris_tabu_search_vrp(problem, max_iterations = 25L)
assert_true(tabu_sol$vehicle_count >= 1L, "Tabu search returns non-empty fleet solution")
assert_true(tabu_sol$total_distance_meters > 0.0, "Total distance is positive")
for (r in tabu_sol$routes) {
  assert_true(r$load <= 80.0, "Tabu route respects vehicle capacity")
}

# Test 4: Time Windows Feasibility
sched <- evaluate_vrptw_schedule(c("C1", "C2", "C3"), problem, departure_time_sec = 28800.0)
assert_true(sched$is_feasible, "Schedule within due times must be feasible")
assert_true(sched$total_duration_sec > 0.0, "Duration is positive")
