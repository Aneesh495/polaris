# Polaris Logistics: Tabu Search Metaheuristic for Vehicle Routing
# Memory-based neighborhood exploration with tabu tenure and aspiration criteria

#' Tabu Search VRP Optimizer
#'
#' Explores combinatorial solution space using dynamic memory tabu lists to escape
#' local optima and optimize total fleet distance.
#'
#' @param problem polaris_vrp_problem object
#' @param max_iterations Number of search iterations (default 50)
#' @param tabu_tenure Iterations a customer move remains forbidden (default 8)
#' @return List of optimized routes with distance and load summaries
#' @export
polaris_tabu_search_vrp <- function(problem, max_iterations = 50L, tabu_tenure = 8L) {
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

  total_fleet_dist <- function(r_list) {
    sum(vapply(r_list, route_dist, numeric(1)))
  }

  # Initial solution from Clarke-Wright
  cw_res <- clarke_wright_savings(problem)
  curr_routes <- lapply(cw_res, function(r) r$customers)
  # Optimize each initial route with 2-opt
  curr_routes <- lapply(curr_routes, function(r) two_opt_tour(r, depot_id, d_mat))

  best_routes <- curr_routes
  best_cost <- total_fleet_dist(best_routes)

  # Tabu list: customer_id -> iteration until which moving customer is tabu
  tabu_map <- new.env(hash = TRUE, parent = emptyenv())

  for (iter in seq_len(max_iterations)) {
    best_move <- NULL
    best_move_cost <- Inf

    n_r <- length(curr_routes)
    if (n_r < 2L) break

    # Evaluate neighborhood moves (relocate customer from r1 to r2)
    for (r1 in seq_len(n_r)) {
      if (length(curr_routes[[r1]]) <= 1L) next
      for (r2 in seq_len(n_r)) {
        if (r1 == r2) next

        for (pos1 in seq_along(curr_routes[[r1]])) {
          cust <- curr_routes[[r1]][pos1]

          # Capacity check in r2
          cur_load2 <- sum(demands[curr_routes[[r2]]])
          if (cur_load2 + demands[[cust]] > cap) next

          rem_r1 <- curr_routes[[r1]][-pos1]

          for (pos2 in 0:length(curr_routes[[r2]])) {
            cand_r2 <- if (pos2 == 0) c(cust, curr_routes[[r2]])
                       else if (pos2 == length(curr_routes[[r2]])) c(curr_routes[[r2]], cust)
                       else c(curr_routes[[r2]][1:pos2], cust, curr_routes[[r2]][(pos2 + 1):length(curr_routes[[r2]])])

            # Apply 2-opt locally
            cand_r2 <- two_opt_tour(cand_r2, depot_id, d_mat)

            # Construct candidate fleet
            cand_fleet <- curr_routes
            cand_fleet[[r1]] <- rem_r1
            cand_fleet[[r2]] <- cand_r2
            cand_cost <- total_fleet_dist(cand_fleet)

            # Check Tabu status
            tabu_until <- tabu_map[[cust]]
            is_tabu <- !is.null(tabu_until) && (iter < tabu_until)

            # Aspiration criterion: tabu status overridden if strictly beats best known
            if (is_tabu && cand_cost < best_cost - 1e-4) {
              is_tabu <- FALSE
            }

            if (!is_tabu && cand_cost < best_move_cost) {
              best_move_cost <- cand_cost
              best_move <- list(
                r1 = r1, r2 = r2,
                rem_r1 = rem_r1, cand_r2 = cand_r2,
                cust = cust,
                cost = cand_cost
              )
            }
          }
        }
      }
    }

    if (is.null(best_move)) break

    # Apply best move
    curr_routes[[best_move$r1]] <- best_move$rem_r1
    curr_routes[[best_move$r2]] <- best_move$cand_r2
    tabu_map[[best_move$cust]] <- iter + tabu_tenure

    if (best_move$cost < best_cost - 1e-4) {
      best_cost <- best_move$cost
      best_routes <- curr_routes
    }
  }

  # Drop empty routes
  best_routes <- Filter(function(r) length(r) > 0L, best_routes)

  # Final summary
  final_routes <- list()
  for (idx in seq_along(best_routes)) {
    r_custs <- best_routes[[idx]]
    final_routes[[idx]] <- list(
      route_id = sprintf("route_%d", idx),
      customers = r_custs,
      stops = c(depot_id, r_custs, depot_id),
      load = sum(demands[r_custs]),
      distance_meters = route_dist(r_custs)
    )
  }

  structure(
    list(
      routes = final_routes,
      total_distance_meters = sum(vapply(final_routes, function(r) r$distance_meters, numeric(1))),
      vehicle_count = length(final_routes)
    ),
    class = "polaris_vrp_solution"
  )
}
