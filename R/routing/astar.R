# Polaris Routing Engine: Directed A* Shortest Path Search
# Admissible, monotonic heuristics for goal-directed spatial acceleration

#' Spatial A* Search Heuristics
#'
#' @param u_coord polaris_coordinate object
#' @param t_coord polaris_coordinate object
#' @param metric 'distance' or 'time'
#' @param max_speed_kmh Maximum road speed limit in network for time heuristic
#' @export
astar_heuristic <- function(u_coord, t_coord, metric = "distance",
                            type = "haversine", max_speed_kmh = 120.0) {
  if (type == "zero") return(0.0)

  dist_m <- haversine_distance(u_coord$lat, u_coord$lon, t_coord$lat, t_coord$lon)
  if (metric == "distance") {
    return(dist_m)
  }

  # For time metric: h(u) = distance / max_speed_mps (strictly admissible)
  max_speed_mps <- max(1.0, max_speed_kmh * (1000.0 / 3600.0))
  dist_m / max_speed_mps
}

#' Directed A* Shortest Path Algorithm
#'
#' Evaluates f(u) = g(u) + h(u, target) to prioritize search progress
#' toward the destination coordinates.
#'
#' @param graph polaris_graph object with built CSR
#' @param source_id Character identifier of origin node
#' @param target_id Character identifier of destination node
#' @param metric 'distance' or 'time'
#' @param heuristic_type 'haversine', 'euclidean', or 'zero'
#' @param max_speed_kmh Maximum network speed in km/h for time metric consistency
#' @return polaris_route_result object
#' @export
polaris_astar <- function(graph, source_id, target_id, metric = "distance",
                          heuristic_type = "haversine", max_speed_kmh = 120.0) {
  if (!graph$csr_built) graph$build_csr()

  s_str <- as.character(source_id)
  t_str <- as.character(target_id)
  s_idx <- graph$node_to_idx[[s_str]]
  t_idx <- graph$node_to_idx[[t_str]]

  if (is.null(s_idx)) stop(sprintf("polaris_astar: source node '%s' not found", s_str))
  if (is.null(t_idx)) stop(sprintf("polaris_astar: target node '%s' not found", t_str))

  if (s_idx == t_idx) {
    return(polaris_route_result(
      nodes = s_str,
      edges = character(0),
      total_distance = 0.0,
      total_time = 0.0,
      algorithm = "astar",
      status = "OK"
    ))
  }

  n <- graph$node_count()
  use_time <- (metric == "time")
  target_coord <- graph$node_coords[[t_str]]

  # State vectors
  g_score <- rep(Inf, n)
  f_score <- rep(Inf, n)
  parent_node <- integer(n)
  parent_edge <- character(n)
  closed <- logical(n)

  pq <- polaris_indexed_pq(initial_capacity = min(1024L, n))

  # Initialize source
  g_score[s_idx] <- 0.0
  h_s <- astar_heuristic(graph$node_coords[[s_str]], target_coord,
                         metric = metric, type = heuristic_type,
                         max_speed_kmh = max_speed_kmh)
  f_score[s_idx] <- h_s
  pq$push(as.character(s_idx), f_score[s_idx])

  nodes_explored <- 0L

  while (!pq$is_empty()) {
    top <- pq$pop()
    u <- as.integer(top$element)

    if (closed[u]) next
    closed[u] <- TRUE
    nodes_explored <- nodes_explored + 1L

    # Goal reached
    if (u == t_idx) {
      break
    }

    # Expand neighbors
    start_e <- graph$fwd_offsets[u]
    end_e <- graph$fwd_offsets[u + 1L] - 1L

    if (start_e <= end_e) {
      for (e_ptr in start_e:end_e) {
        v <- graph$fwd_targets[e_ptr]
        if (closed[v]) next

        edge_cost <- if (use_time) graph$fwd_times[e_ptr] else graph$fwd_weights[e_ptr]
        tentative_g <- g_score[u] + edge_cost

        if (tentative_g < g_score[v]) {
          g_score[v] <- tentative_g
          v_id <- graph$idx_to_node[v]
          h_v <- astar_heuristic(graph$node_coords[[v_id]], target_coord,
                                 metric = metric, type = heuristic_type,
                                 max_speed_kmh = max_speed_kmh)
          f_v <- tentative_g + h_v
          f_score[v] <- f_v
          parent_node[v] <- u
          parent_edge[v] <- graph$fwd_edge_ids[e_ptr]
          pq$push(as.character(v), f_v)
        }
      }
    }
  }

  if (!closed[t_idx] && is.infinite(g_score[t_idx])) {
    return(polaris_route_result(
      nodes = character(0),
      edges = character(0),
      total_distance = Inf,
      total_time = Inf,
      algorithm = "astar",
      status = "NO_PATH_FOUND"
    ))
  }

  # Backtrack path
  curr <- t_idx
  path_nodes_idx <- integer(0)
  path_edges <- character(0)

  while (curr != 0L && curr != s_idx) {
    path_nodes_idx <- c(curr, path_nodes_idx)
    path_edges <- c(parent_edge[curr], path_edges)
    curr <- parent_node[curr]
  }
  path_nodes_idx <- c(s_idx, path_nodes_idx)
  path_node_ids <- graph$idx_to_node[path_nodes_idx]

  # Calculate total distance, total time, and geometry
  tot_dist <- 0.0
  tot_time <- 0.0
  geom_list <- list()

  for (e_id in path_edges) {
    edge_obj <- graph$get_edge(e_id)
    if (!is.null(edge_obj)) {
      tot_dist <- tot_dist + edge_obj$distance
      tot_time <- tot_time + edge_obj$travel_time
    }
  }
  for (nd_id in path_node_ids) {
    geom_list[[length(geom_list) + 1L]] <- graph$node_coords[[nd_id]]
  }

  polaris_route_result(
    nodes = path_node_ids,
    edges = path_edges,
    total_distance = tot_dist,
    total_time = tot_time,
    geometry = geom_list,
    algorithm = "astar",
    status = "OK"
  )
}
