# Unit Tests: Traffic Assignment, BPR Delay Functions, and Frank-Wolfe Equilibrium

# Test 1: BPR Delay Function Properties
t_free <- bpr_travel_time(free_flow_time = 100.0, flow = 0.0, capacity = 1000.0)
assert_equal(t_free, 100.0, "Zero flow gives exact free flow time")

t_cap <- bpr_travel_time(free_flow_time = 100.0, flow = 1000.0, capacity = 1000.0)
# 100 * (1 + 0.15 * 1^4) = 115.0
assert_equal(t_cap, 115.0, "At capacity v/c=1.0 travel time increases by alpha=15%")

t_heavy <- bpr_travel_time(free_flow_time = 100.0, flow = 2000.0, capacity = 1000.0)
# 100 * (1 + 0.15 * 2^4) = 100 * (1 + 2.4) = 340.0
assert_equal(t_heavy, 340.0, "At 2x capacity travel time increases heavily to 340s")

# Test 2: BPR Integral and Numerical Derivative Consistency
# Finite difference derivative of integral should match travel time
fl <- 500.0
eps <- 1e-5
int_plus <- bpr_integral(100.0, fl + eps, 1000.0)
int_minus <- bpr_integral(100.0, fl - eps, 1000.0)
num_deriv <- (int_plus - int_minus) / (2.0 * eps)
ana_val <- bpr_travel_time(100.0, fl, 1000.0)
assert_equal(num_deriv, ana_val, "Integral derivative matches BPR travel time", tol = 1e-4)

# Test 3: Frank-Wolfe Equilibrium on Braess Paradox Network
# 4 nodes: A, B, C, D
# A -> B -> D (upper route)
# A -> C -> D (lower route)
braess_g <- polaris_graph()
braess_g$add_node("A", 0.0, 0.0)
braess_g$add_node("B", 1.0, 0.5)
braess_g$add_node("C", 1.0, -0.5)
braess_g$add_node("D", 2.0, 0.0)

# Links:
# A -> B: congested
braess_g$add_edge("e_AB", "A", "B", distance = 1000.0, travel_time = 50.0, speed_limit = 50.0, oneway = TRUE)
# B -> D: fixed time
braess_g$add_edge("e_BD", "B", "D", distance = 1000.0, travel_time = 150.0, speed_limit = 50.0, oneway = TRUE)
# A -> C: fixed time
braess_g$add_edge("e_AC", "A", "C", distance = 1000.0, travel_time = 150.0, speed_limit = 50.0, oneway = TRUE)
# C -> D: congested
braess_g$add_edge("e_CD", "C", "D", distance = 1000.0, travel_time = 50.0, speed_limit = 50.0, oneway = TRUE)

braess_g$build_csr()

# Demand of 1000 vehicles from A to D
od_mat <- matrix(0.0, nrow = 4, ncol = 4, dimnames = list(c("A","B","C","D"), c("A","B","C","D")))
od_mat["A", "D"] <- 1000.0

caps <- c("e_AB" = 1000.0, "e_BD" = 2000.0, "e_AC" = 2000.0, "e_CD" = 1000.0)

fw_res <- polaris_frank_wolfe(braess_g, od_mat, capacities = caps, max_iterations = 20L, target_relative_gap = 1e-3)

# In symmetric 2-route network, equilibrium flow must be split 500 / 500
assert_equal(fw_res$flows["e_AB"], 500.0, "Symmetric upper route gets 500 vehicles", tol = 5.0)
assert_equal(fw_res$flows["e_CD"], 500.0, "Symmetric lower route gets 500 vehicles", tol = 5.0)
assert_true(fw_res$relative_gap < 0.01, "Relative gap converged below 1%")
