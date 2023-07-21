# Polaris Routing Engine: ALT (A*, Landmarks, Triangle Inequality) Preprocessor & Query
# Uses precomputed landmark distances to yield tight, admissible lower bounds

#' Select Strategic Landmark Vertices
#'
#' Places landmarks around the network perimeter using the max-cover furthest-node heuristic.
#'
#' @param graph polaris_graph object
#' @param n_landmarks Number of landmarks to select (e.g. 4 to 16)
#' @return Character vector of landmark node IDs
#' @export
alt_select_landmarks <- function(graph, n_landmarks = 8L) {
  if (!graph$csr_built) graph$build_csr()
  n <- graph$node_count()
  k <- min(as.integer(n_landmarks), n)
  if (k <= 0L) return(character(0))

  landmarks <- character(k)
  # Pick initial node arbitrarily
  landmarks[1L] <- graph$node_ids[1L]

  # Distance matrix: dist from landmarks
  min_dist <- rep(Inf, n)

  for (i in seq_len(k)) {
    curr_lm <- landmarks[i]
    dijk_res <- polaris_dijkstra(graph, source_id = curr_lm)

    # Update minimum distance to any selected landmark
    valid_dists <- dijk_res$distances
    valid_dists[is.infinite(valid_dists)] <- 1e12
    min_dist <- pmin(min_dist, valid_dists)

    # Next landmark is the node furthest from all existing landmarks
    if (i < k) {
      next_idx <- which.max(min_dist)
      landmarks[i + 1L] <- graph$idx_to_node[next_idx]
    }
  }

  landmarks
}

#' Precompute Landmark Distances for ALT Algorithm
#'
#' Computes all-to-landmark and landmark-to-all distances for all selected landmarks.
#'
#' @param graph polaris_graph object
#' @param landmarks Character vector of landmark node IDs
#' @param metric 'distance' or 'time'
#' @return An environment-based polaris_alt_index
#' @export
alt_preprocess <- function(graph, landmarks = NULL, n_landmarks = 8L, metric = "distance") {
  if (!graph$csr_built) graph$build_csr()
  if (is.null(landmarks)) {
    landmarks <- alt_select_landmarks(graph, n_landmarks = n_landmarks)
  }

  n <- graph$node_count()
  k <- length(landmarks)

  # D_from_lm[i, v]: distance from landmark i to node v
  d_from_lm <- matrix(Inf, nrow = k, ncol = n)
  # D_to_lm[i, v]: distance from node v to landmark i
  d_to_lm <- matrix(Inf, nrow = k, ncol = n)

  for (i in seq_len(k)) {
    lm_id <- landmarks[i]
    # Landmark to all nodes (forward search)
    fwd_res <- polaris_dijkstra(graph, source_id = lm_id, metric = metric)
    d_from_lm[i, ] <- if (metric == "time") fwd_res$travel_times else fwd_res$distances

    # All nodes to landmark (backward search from landmark)
    # Using backward CSR
    lm_idx <- graph$node_to_idx[[lm_id]]
    bwd_dist <- rep(Inf, n)
    pq <- polaris_indexed_pq(initial_capacity = min(1024L, n))
    bwd_dist[lm_idx] <- 0.0
    pq$push(as.character(lm_idx), 0.0)

    use_time <- (metric == "time")
    settled <- logical(n)

    while (!pq$is_empty()) {
      top <- pq$pop()
      u <- as.integer(top$element)
      if (settled[u]) next
      settled[u] <- TRUE

      start_e <- graph$bwd_offsets[u]
      end_e <- graph$bwd_offsets[u + 1L] - 1L
      if (start_e <= end_e) {
        for (e_ptr in start_e:end_e) {
          v <- graph$bwd_targets[e_ptr]
          if (settled[v]) next
          cost_e <- if (use_time) graph$bwd_times[e_ptr] else graph$bwd_weights[e_ptr]
          new_cost <- bwd_dist[u] + cost_e
          if (new_cost < bwd_dist[v]) {
            bwd_dist[v] <- new_cost
            pq$push(as.character(v), new_cost)
          }
        }
      }
    }
    d_to_lm[i, ] <- bwd_dist
  }

  idx_env <- new.env(parent = emptyenv())
  idx_env$landmarks <- landmarks
  idx_env$d_from_lm <- d_from_lm
  idx_env$d_to_lm <- d_to_lm
  idx_env$metric <- metric
  idx_env$graph <- graph

  # Heuristic calculation: lower bound from u to target t
  idx_env$heuristic <- function(u_idx, t_idx) {
    # Triangle inequality lower bounds:
    # 1. d(u, t) >= d(L, t) - d(L, u)
    # 2. d(u, t) >= d(u, L) - d(t, L)
    b1 <- idx_env$d_from_lm[, t_idx] - idx_env$d_from_lm[, u_idx]
    b2 <- idx_env$d_to_lm[, u_idx] - idx_env$d_to_lm[, t_idx]
    max(0.0, max(b1, na.rm = TRUE), max(b2, na.rm = TRUE))
  }

  structure(idx_env, class = "polaris_alt_index")
}

#' Query Shortest Path Using ALT Precomputed Landmarks
#'
#' @param alt_index polaris_alt_index object from alt_preprocess()
#' @param source_id Origin node identifier
#' @param target_id Destination node identifier
#' @return polaris_route_result object
#' @export
polaris_alt_route <- function(alt_index, source_id, target_id) {
  g <- alt_index$graph
  if (!g$csr_built) g$build_csr()

  s_str <- as.character(source_id)
  t_str <- as.character(target_id)
  s_idx <- g$node_to_idx[[s_str]]
  t_idx <- g$node_to_idx[[t_str]]

  if (is.null(s_idx)) stop(sprintf("alt_route: source '%s' not found", s_str))
  if (is.null(t_idx)) stop(sprintf("alt_route: target '%s' not found", t_str))

  if (s_idx == t_idx) {
    return(polaris_route_result(
      nodes = s_str,
      edges = character(0),
      total_distance = 0.0,
      total_time = 0.0,
      algorithm = "alt",
      status = "OK"
    ))
  }

  n <- g$node_count()
  use_time <- (alt_index$metric == "time")

  g_score <- rep(Inf, n)
  f_score <- rep(Inf, n)
  parent_node <- integer(n)
  parent_edge <- character(n)
  closed <- logical(n)

  pq <- polaris_indexed_pq(initial_capacity = min(1024L, n))

  g_score[s_idx] <- 0.0
  h_s <- alt_index$heuristic(s_idx, t_idx)
  f_score[s_idx] <- h_s
  pq$push(as.character(s_idx), f_score[s_idx])

  while (!pq$is_empty()) {
    top <- pq$pop()
    u <- as.integer(top$element)

    if (closed[u]) next
    closed[u] <- TRUE

    if (u == t_idx) break

    start_e <- g$fwd_offsets[u]
    end_e <- g$fwd_offsets[u + 1L] - 1L

    if (start_e <= end_e) {
      for (e_ptr in start_e:end_e) {
        v <- g$fwd_targets[e_ptr]
        if (closed[v]) next

        edge_cost <- if (use_time) g$fwd_times[e_ptr] else g$fwd_weights[e_ptr]
        tentative_g <- g_score[u] + edge_cost

        if (tentative_g < g_score[v]) {
          g_score[v] <- tentative_g
          h_v <- alt_index$heuristic(v, t_idx)
          f_v <- tentative_g + h_v
          f_score[v] <- f_v
          parent_node[v] <- u
          parent_edge[v] <- g$fwd_edge_ids[e_ptr]
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
      algorithm = "alt",
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
  path_node_ids <- g$idx_to_node[path_nodes_idx]

  tot_dist <- 0.0
  tot_time <- 0.0
  geom_list <- list()

  for (e_id in path_edges) {
    edge_obj <- g$get_edge(e_id)
    if (!is.null(edge_obj)) {
      tot_dist <- tot_dist + edge_obj$distance
      tot_time <- tot_time + edge_obj$travel_time
    }
  }
  for (nd_id in path_node_ids) {
    geom_list[[length(geom_list) + 1L]] <- g$node_coords[[nd_id]]
  }

  polaris_route_result(
    nodes = path_node_ids,
    edges = path_edges,
    total_distance = tot_dist,
    total_time = tot_time,
    geometry = geom_list,
    algorithm = "alt",
    status = "OK"
  )
}
