# Polaris Logistics: Clarke-Wright Parallel Savings Heuristic
# Generates high-quality initial CVRP tours by maximizing return-to-depot savings

#' Clarke-Wright Savings Tour Construction
#'
#' Evaluates savings s_{i, j} = d(0, i) + d(0, j) - d(i, j) to greedily merge
#' back-and-forth customer tours subject to vehicle capacity constraints.
#'
#' @param problem polaris_vrp_problem object
#' @return List of routes, each containing customer sequence, load, and total distance
#' @export
clarke_wright_savings <- function(problem) {
  depot_id <- problem$depot$id
  cust_ids <- problem$customer_ids
  d_mat <- problem$distance_matrix
  cap <- problem$vehicle_capacity

  n_cust <- length(cust_ids)
  if (n_cust == 0L) return(list())

  # Customer demands lookup
  demands <- setNames(vapply(problem$customers, function(c) c$demand, numeric(1)), cust_ids)

  # Initial state: each customer is on its own route depot -> i -> depot
  # routes is a list of customer character vectors
  routes <- lapply(cust_ids, function(id) c(id))
  route_loads <- vapply(cust_ids, function(id) demands[[id]], numeric(1))

  # Calculate all pairwise savings: s_ij = d(0, i) + d(0, j) - d(i, j)
  savings_list <- list()
  for (i in seq_len(n_cust - 1L)) {
    c_i <- cust_ids[i]
    d_0i <- d_mat[depot_id, c_i]
    for (j in seq(i + 1L, n_cust)) {
      c_j <- cust_ids[j]
      d_0j <- d_mat[depot_id, c_j]
      d_ij <- d_mat[c_i, c_j]

      s_val <- d_0i + d_0j - d_ij
      if (s_val > 0.0) {
        savings_list[[length(savings_list) + 1L]] <- list(
          i = c_i,
          j = c_j,
          savings = s_val
        )
      }
    }
  }

  # Sort savings descending
  if (length(savings_list) > 1L) {
    s_vals <- vapply(savings_list, function(s) s$savings, numeric(1))
    savings_list <- savings_list[order(s_vals, decreasing = TRUE)]
  }

  # Greedily merge routes
  for (s_entry in savings_list) {
    ci <- s_entry$i
    cj <- s_entry$j

    # Find routes containing ci and cj
    r_idx_i <- which(vapply(routes, function(r) ci %in% r, logical(1)))
    r_idx_j <- which(vapply(routes, function(r) cj %in% r, logical(1)))

    if (length(r_idx_i) != 1L || length(r_idx_j) != 1L) next
    if (r_idx_i == r_idx_j) next # Already on the same route

    r_i <- routes[[r_idx_i]]
    r_j <- routes[[r_idx_j]]

    # Check capacity feasibility
    comb_load <- route_loads[r_idx_i] + route_loads[r_idx_j]
    if (comb_load > cap) next

    # Can merge only if ci and cj are exterior endpoints of their respective routes
    # Case 1: ci is last in r_i, cj is first in r_j -> r_i + r_j
    # Case 2: cj is last in r_j, ci is first in r_i -> r_j + r_i
    # Case 3: ci is first in r_i, cj is first in r_j -> rev(r_i) + r_j
    # Case 4: ci is last in r_i, cj is last in r_j -> r_i + rev(r_j)
    new_route <- NULL

    is_i_first <- (r_i[1L] == ci)
    is_i_last  <- (r_i[length(r_i)] == ci)
    is_j_first <- (r_j[1L] == cj)
    is_j_last  <- (r_j[length(r_j)] == cj)

    if (is_i_last && is_j_first) {
      new_route <- c(r_i, r_j)
    } else if (is_j_last && is_i_first) {
      new_route <- c(r_j, r_i)
    } else if (is_i_first && is_j_first) {
      new_route <- c(rev(r_i), r_j)
    } else if (is_i_last && is_j_last) {
      new_route <- c(r_i, rev(r_j))
    }

    if (!is.null(new_route)) {
      # Remove old routes and append merged route
      keep_idx <- setdiff(seq_along(routes), c(r_idx_i, r_idx_j))
      routes <- c(routes[keep_idx], list(new_route))
      route_loads <- c(route_loads[keep_idx], comb_load)
    }
  }

  # Build route summary objects
  final_routes <- list()
  for (idx in seq_along(routes)) {
    r_custs <- routes[[idx]]
    # Calculate route total distance: depot -> c1 -> c2 -> ... -> cn -> depot
    tot_d <- d_mat[depot_id, r_custs[1L]]
    if (length(r_custs) > 1L) {
      for (k in seq_len(length(r_custs) - 1L)) {
        tot_d <- tot_d + d_mat[r_custs[k], r_custs[k + 1L]]
      }
    }
    tot_d <- tot_d + d_mat[r_custs[length(r_custs)], depot_id]

    final_routes[[idx]] <- list(
      route_id = sprintf("route_%d", idx),
      customers = r_custs,
      stops = c(depot_id, r_custs, depot_id),
      load = route_loads[idx],
      distance_meters = tot_d
    )
  }

  final_routes
}
