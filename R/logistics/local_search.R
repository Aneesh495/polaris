# Polaris Logistics: Local Search Operators (2-opt, Relocate, Swap)
# Intra-route tour untangling and inter-route neighborhood improvement operators

#' 2-Opt Intra-Route Optimization
#'
#' Iteratively reverses sub-segments of a vehicle tour whenever doing so reduces
#' total traveled distance, eliminating crossing edges.
#'
#' @param tour Character vector of customer IDs (excluding depot)
#' @param depot_id Depot ID string
#' @param d_mat Distance matrix
#' @return Improved customer sequence
#' @export
two_opt_tour <- function(tour, depot_id, d_mat) {
  n <- length(tour)
  if (n <= 2L) return(tour)

  tour_dist <- function(t_seq) {
    tot <- d_mat[depot_id, t_seq[1L]]
    for (i in seq_len(length(t_seq) - 1L)) {
      tot <- tot + d_mat[t_seq[i], t_seq[i + 1L]]
    }
    tot + d_mat[t_seq[length(t_seq)], depot_id]
  }

  best_dist <- tour_dist(tour)
  improved <- TRUE

  while (improved) {
    improved <- FALSE
    for (i in 1:(n - 1L)) {
      for (j in (i + 1L):n) {
        # Reverse sub-sequence between i and j
        new_tour <- tour
        new_tour[i:j] <- rev(tour[i:j])
        new_d <- tour_dist(new_tour)

        if (new_d < best_dist - 1e-4) {
          best_dist <- new_d
          tour <- new_tour
          improved <- TRUE
          break
        }
      }
      if (improved) break
    }
  }

  tour
}

#' Relocate Neighborhood Operator
#'
#' Tries moving single customers between different vehicle routes to reduce fleet mileage.
#'
#' @param routes List of customer ID vectors
#' @param problem polaris_vrp_problem object
#' @return Improved routes list
#' @export
relocate_operator <- function(routes, problem) {
  depot_id <- problem$depot$id
  d_mat <- problem$distance_matrix
  cap <- problem$vehicle_capacity
  demands <- setNames(vapply(problem$customers, function(c) c$demand, numeric(1)), problem$customer_ids)

  route_dist <- function(t_seq) {
    if (length(t_seq) == 0L) return(0.0)
    tot <- d_mat[depot_id, t_seq[1L]]
    if (length(t_seq) > 1L) {
      for (i in seq_len(length(t_seq) - 1L)) {
        tot <- tot + d_mat[t_seq[i], t_seq[i + 1L]]
      }
    }
    tot + d_mat[t_seq[length(t_seq)], depot_id]
  }

  route_load <- function(t_seq) {
    sum(demands[t_seq])
  }

  n_r <- length(routes)
  if (n_r < 2L) return(routes)

  improved <- TRUE
  while (improved) {
    improved <- FALSE
    for (r1 in seq_len(n_r)) {
      for (r2 in seq_len(n_r)) {
        if (r1 == r2 || length(routes[[r1]]) <= 1L) next

        for (pos1 in seq_along(routes[[r1]])) {
          cust <- routes[[r1]][pos1]
          # Check capacity in r2
          if (route_load(routes[[r2]]) + demands[[cust]] > cap) next

          rem_r1 <- routes[[r1]][-pos1]
          orig_cost <- route_dist(routes[[r1]]) + route_dist(routes[[r2]])

          # Try inserting cust at all possible positions in r2
          for (pos2 in 0:length(routes[[r2]])) {
            cand_r2 <- if (pos2 == 0) c(cust, routes[[r2]])
                       else if (pos2 == length(routes[[r2]])) c(routes[[r2]], cust)
                       else c(routes[[r2]][1:pos2], cust, routes[[r2]][(pos2 + 1):length(routes[[r2]])])

            cand_cost <- route_dist(rem_r1) + route_dist(cand_r2)
            if (cand_cost < orig_cost - 1e-4) {
              routes[[r1]] <- rem_r1
              routes[[r2]] <- cand_r2
              improved <- TRUE
              break
            }
          }
          if (improved) break
        }
        if (improved) break
      }
      if (improved) break
    }
  }

  routes
}
