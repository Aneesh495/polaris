# Polaris Traffic Assignment: Frank-Wolfe Convex User Equilibrium
# Solves Beckmann's mathematical optimization program via line search

#' Frank-Wolfe Convex Traffic Equilibrium Optimization
#'
#' Iteratively optimizes link traffic flow assignments to achieve Wardrop User Equilibrium
#' where no driver can unilaterally improve their travel time by choosing an alternative route.
#'
#' @param graph Base polaris_graph road network
#' @param od_matrix Origin-Destination demand matrix (vehicles/hour)
#' @param capacities Named numeric vector of edge design capacities (vehicles/hour)
#' @param max_iterations Maximum Frank-Wolfe iterations (default 30)
#' @param target_relative_gap Convergence threshold on relative gap (default 1e-4)
#' @param alpha BPR alpha parameter (default 0.15)
#' @param beta BPR beta parameter (default 4.0)
#' @return S3 object of class polaris_traffic_equilibrium
#' @export
polaris_frank_wolfe <- function(graph, od_matrix, capacities,
                                max_iterations = 30L,
                                target_relative_gap = 1e-4,
                                alpha = DEFAULT_BPR_ALPHA,
                                beta = DEFAULT_BPR_BETA) {
  if (!graph$csr_built) graph$build_csr()
  edge_ids <- graph$edge_ids
  n_edges <- length(edge_ids)

  # Extract free-flow travel times and default capacities
  t0 <- numeric(n_edges)
  caps <- numeric(n_edges)
  for (i in seq_len(n_edges)) {
    e_id <- edge_ids[i]
    e_obj <- graph$get_edge(e_id)
    t0[i] <- e_obj$travel_time
    caps[i] <- if (!is.null(capacities[[e_id]])) as.numeric(capacities[[e_id]]) else 1800.0 # default lane cap
  }

  names(t0) <- edge_ids
  names(caps) <- edge_ids

  cat(sprintf("[polaris-traffic] Commencing Frank-Wolfe User Equilibrium (%d edges, max_iter=%d)...\n",
              n_edges, max_iterations))

  # Iteration 0: All-or-Nothing assignment on free-flow travel times
  for (i in seq_len(n_edges)) {
    graph$edges[[edge_ids[i]]]$travel_time <- t0[i]
  }
  graph$build_csr()

  x_current <- all_or_nothing_assignment(graph, od_matrix)

  iteration_history <- list()

  for (iter in seq_len(max_iterations)) {
    # 1. Update link travel times with BPR function
    t_congested <- numeric(n_edges)
    names(t_congested) <- edge_ids
    for (i in seq_len(n_edges)) {
      e_id <- edge_ids[i]
      t_congested[i] <- bpr_travel_time(
        free_flow_time = t0[i],
        flow = x_current[i],
        capacity = caps[i],
        alpha = alpha,
        beta = beta
      )
      graph$edges[[e_id]]$travel_time <- t_congested[i]
    }
    graph$build_csr()

    # 2. Compute descent direction via All-or-Nothing on congested times
    y_aux <- all_or_nothing_assignment(graph, od_matrix)

    # 3. Compute relative gap
    # Total travel time under current flow: sum(x * t(x))
    # Lower bound on total travel time: sum(y * t(x))
    total_travel_time <- sum(x_current * t_congested)
    lower_bound <- sum(y_aux * t_congested)
    gap <- max(0.0, total_travel_time - lower_bound)
    rel_gap <- if (total_travel_time > 0) gap / total_travel_time else 0.0

    iteration_history[[iter]] <- list(
      iteration = iter,
      relative_gap = rel_gap,
      beckmann_objective = sum(vapply(seq_len(n_edges), function(i) {
        bpr_integral(t0[i], x_current[i], caps[i], alpha = alpha, beta = beta)
      }, numeric(1)))
    )

    if (rel_gap <= target_relative_gap) {
      cat(sprintf("[polaris-traffic] Converged at iteration %d with relative gap %.6e <= %.6e\n",
                  iter, rel_gap, target_relative_gap))
      break
    }

    # 4. Line search for optimal step size lambda in [0, 1] using Bisection
    # Derivative of Beckmann objective with respect to lambda:
    # dObj/dlambda = sum_e (y_e - x_e) * t_e(x_e + lambda * (y_e - x_e))
    eval_derivative <- function(lambda) {
      deriv_sum <- 0.0
      for (i in seq_len(n_edges)) {
        diff_e <- y_aux[i] - x_current[i]
        flow_e <- x_current[i] + lambda * diff_e
        t_e <- bpr_travel_time(t0[i], flow_e, caps[i], alpha = alpha, beta = beta)
        deriv_sum <- deriv_sum + diff_e * t_e
      }
      deriv_sum
    }

    low_lam <- 0.0
    high_lam <- 1.0
    for (step in 1:15) { # 15 bisection iterations gives < 1e-4 accuracy
      mid_lam <- (low_lam + high_lam) / 2.0
      d_val <- eval_derivative(mid_lam)
      if (d_val > 0.0) {
        high_lam <- mid_lam
      } else {
        low_lam <- mid_lam
      }
    }
    opt_lambda <- (low_lam + high_lam) / 2.0

    # 5. Flow update: x = x + lambda * (y - x)
    x_current <- x_current + opt_lambda * (y_aux - x_current)
  }

  # Final summary metrics
  vc_ratios <- x_current / caps

  structure(
    list(
      flows = x_current,
      travel_times = t_congested,
      vc_ratios = vc_ratios,
      free_flow_times = t0,
      capacities = caps,
      total_system_travel_time = sum(x_current * t_congested),
      relative_gap = rel_gap,
      history = iteration_history
    ),
    class = "polaris_traffic_equilibrium"
  )
}
