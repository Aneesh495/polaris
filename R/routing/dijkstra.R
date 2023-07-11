# Polaris Routing Engine: Unidirectional and Multi-Target Dijkstra
# Optimal shortest path search with predecessor tracking and CSR acceleration

#' Unidirectional Dijkstra Shortest Path Search
#'
#' Computes the minimum cost path between origin and destination vertices
#' using an addressable min-heap priority queue over CSR adjacency structures.
#'
#' @param graph polaris_graph object with built CSR
#' @param source_id Character or integer identifier of origin node
#' @param target_id Character or integer identifier of target node (optional)
#' @param metric Cost metric to minimize: 'distance' (meters) or 'time' (seconds)
#' @return polaris_route_result object
#' @export
polaris_dijkstra <- function(graph, source_id, target_id = NULL, metric = "distance") {
  if (!graph$csr_built) graph$build_csr()

  s_str <- as.character(source_id)
  s_idx <- graph$node_to_idx[[s_str]]
  if (is.null(s_idx)) {
    stop(sprintf("polaris_dijkstra: source node '%s' not found in graph", s_str))
  }

  has_target <- !is.null(target_id)
  t_idx <- NULL
  if (has_target) {
    t_str <- as.character(target_id)
    t_idx <- graph$node_to_idx[[t_str]]
    if (is.null(t_idx)) {
      stop(sprintf("polaris_dijkstra: target node '%s' not found in graph", t_str))
    }
    if (s_idx == t_idx) {
      return(polaris_route_result(
        nodes = s_str,
        edges = character(0),
        total_distance = 0.0,
        total_time = 0.0,
        algorithm = "dijkstra",
        status = "OK"
      ))
    }
  }

  n <- graph$node_count()
  dist <- rep(Inf, n)
  time_arr <- rep(Inf, n)
  parent_node <- integer(n)
  parent_edge <- character(n)
  settled <- logical(n)

  pq <- polaris_indexed_pq(initial_capacity = min(1024L, n))

  dist[s_idx] <- 0.0
  time_arr[s_idx] <- 0.0
  pq$push(as.character(s_idx), 0.0)

  use_time <- (metric == "time")
  nodes_settled <- 0L

  while (!pq$is_empty()) {
    top <- pq$pop()
    u <- as.integer(top$element)
    u_cost <- top$priority

    if (settled[u]) next
    settled[u] <- TRUE
    nodes_settled <- nodes_settled + 1L

    # Early exit if target reached
    if (has_target && u == t_idx) {
      break
    }

    # Relax outgoing edges using CSR flat arrays
    start_e <- graph$fwd_offsets[u]
    end_e <- graph$fwd_offsets[u + 1L] - 1L

    if (start_e <= end_e) {
      for (e_ptr in start_e:end_e) {
        v <- graph$fwd_targets[e_ptr]
        if (settled[v]) next

        edge_len <- graph$fwd_weights[e_ptr]
        edge_time <- graph$fwd_times[e_ptr]
        edge_cost <- if (use_time) edge_time else edge_len

        new_cost <- u_cost + edge_cost
        curr_cost <- if (use_time) time_arr[v] else dist[v]

        if (new_cost < curr_cost) {
          if (use_time) {
            time_arr[v] <- new_cost
            dist[v] <- dist[u] + edge_len
          } else {
            dist[v] <- new_cost
            time_arr[v] <- time_arr[u] + edge_time
          }
          parent_node[v] <- u
          parent_edge[v] <- graph$fwd_edge_ids[e_ptr]
          pq$push(as.character(v), new_cost)
        }
      }
    }
  }

  if (has_target) {
    if (!settled[t_idx] && is.infinite(dist[t_idx])) {
      return(polaris_route_result(
        nodes = character(0),
        edges = character(0),
        total_distance = Inf,
        total_time = Inf,
        algorithm = "dijkstra",
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

    # Reconstruct geometry
    geom_list <- list()
    for (nd_id in path_node_ids) {
      geom_list[[length(geom_list) + 1L]] <- graph$node_coords[[nd_id]]
    }

    polaris_route_result(
      nodes = path_node_ids,
      edges = path_edges,
      total_distance = dist[t_idx],
      total_time = time_arr[t_idx],
      geometry = geom_list,
      algorithm = "dijkstra",
      status = "OK"
    )
  } else {
    # Return distance and predecessor tree for multi-target queries
    list(
      source = s_str,
      distances = dist,
      travel_times = time_arr,
      parent_nodes = parent_node,
      parent_edges = parent_edge,
      settled = settled,
      nodes_settled = nodes_settled
    )
  }
}
