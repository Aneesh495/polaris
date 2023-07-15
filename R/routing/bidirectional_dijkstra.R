# Polaris Routing Engine: Symmetric Bidirectional Dijkstra
# Dual-frontier shortest path search with optimal stopping criteria

#' Bidirectional Dijkstra Shortest Path Search
#'
#' Explores search spaces simultaneously from source and target, terminating
#' as soon as the sum of minimum frontier keys exceeds the best known path.
#'
#' @param graph polaris_graph object with built CSR
#' @param source_id Character or integer identifier of source node
#' @param target_id Character or integer identifier of target node
#' @param metric Cost metric: 'distance' (meters) or 'time' (seconds)
#' @return polaris_route_result object
#' @export
polaris_bidirectional_dijkstra <- function(graph, source_id, target_id, metric = "distance") {
  if (!graph$csr_built) graph$build_csr()

  s_str <- as.character(source_id)
  t_str <- as.character(target_id)
  s_idx <- graph$node_to_idx[[s_str]]
  t_idx <- graph$node_to_idx[[t_str]]

  if (is.null(s_idx)) stop(sprintf("bidirectional_dijkstra: source node '%s' not found", s_str))
  if (is.null(t_idx)) stop(sprintf("bidirectional_dijkstra: target node '%s' not found", t_str))

  if (s_idx == t_idx) {
    return(polaris_route_result(
      nodes = s_str,
      edges = character(0),
      total_distance = 0.0,
      total_time = 0.0,
      algorithm = "bidirectional_dijkstra",
      status = "OK"
    ))
  }

  n <- graph$node_count()
  use_time <- (metric == "time")

  # Forward search state
  dist_fwd <- rep(Inf, n)
  parent_node_fwd <- integer(n)
  parent_edge_fwd <- character(n)
  settled_fwd <- logical(n)
  pq_fwd <- polaris_indexed_pq(initial_capacity = min(1024L, n))

  # Backward search state
  dist_bwd <- rep(Inf, n)
  parent_node_bwd <- integer(n)
  parent_edge_bwd <- character(n)
  settled_bwd <- logical(n)
  pq_bwd <- polaris_indexed_pq(initial_capacity = min(1024L, n))

  dist_fwd[s_idx] <- 0.0
  pq_fwd$push(as.character(s_idx), 0.0)

  dist_bwd[t_idx] <- 0.0
  pq_bwd$push(as.character(t_idx), 0.0)

  best_cost <- Inf
  meet_node <- 0L

  while (!pq_fwd$is_empty() && !pq_bwd$is_empty()) {
    top_fwd <- pq_fwd$peek()
    top_bwd <- pq_bwd$peek()

    # Optimal stopping criterion
    if (top_fwd$priority + top_bwd$priority >= best_cost) {
      break
    }

    # Alternate or choose direction with smaller frontier
    expand_fwd <- (top_fwd$priority <= top_bwd$priority)

    if (expand_fwd) {
      curr <- pq_fwd$pop()
      u <- as.integer(curr$element)
      if (settled_fwd[u]) next
      settled_fwd[u] <- TRUE

      # Check connection with backward search
      if (settled_bwd[u] || !is.infinite(dist_bwd[u])) {
        cand_cost <- dist_fwd[u] + dist_bwd[u]
        if (cand_cost < best_cost) {
          best_cost <- cand_cost
          meet_node <- u
        }
      }

      start_e <- graph$fwd_offsets[u]
      end_e <- graph$fwd_offsets[u + 1L] - 1L
      if (start_e <= end_e) {
        for (e_ptr in start_e:end_e) {
          v <- graph$fwd_targets[e_ptr]
          if (settled_fwd[v]) next
          cost_e <- if (use_time) graph$fwd_times[e_ptr] else graph$fwd_weights[e_ptr]
          new_cost <- dist_fwd[u] + cost_e
          if (new_cost < dist_fwd[v]) {
            dist_fwd[v] <- new_cost
            parent_node_fwd[v] <- u
            parent_edge_fwd[v] <- graph$fwd_edge_ids[e_ptr]
            pq_fwd$push(as.character(v), new_cost)

            # Update best_cost if already reached by backward search
            if (!is.infinite(dist_bwd[v])) {
              cand_cost <- new_cost + dist_bwd[v]
              if (cand_cost < best_cost) {
                best_cost <- cand_cost
                meet_node <- v
              }
            }
          }
        }
      }
    } else {
      # Backward search expansion
      curr <- pq_bwd$pop()
      u <- as.integer(curr$element)
      if (settled_bwd[u]) next
      settled_bwd[u] <- TRUE

      if (settled_fwd[u] || !is.infinite(dist_fwd[u])) {
        cand_cost <- dist_fwd[u] + dist_bwd[u]
        if (cand_cost < best_cost) {
          best_cost <- cand_cost
          meet_node <- u
        }
      }

      # Relax incoming edges using backward CSR
      start_e <- graph$bwd_offsets[u]
      end_e <- graph$bwd_offsets[u + 1L] - 1L
      if (start_e <= end_e) {
        for (e_ptr in start_e:end_e) {
          v <- graph$bwd_targets[e_ptr]
          if (settled_bwd[v]) next
          cost_e <- if (use_time) graph$bwd_times[e_ptr] else graph$bwd_weights[e_ptr]
          new_cost <- dist_bwd[u] + cost_e
          if (new_cost < dist_bwd[v]) {
            dist_bwd[v] <- new_cost
            parent_node_bwd[v] <- u
            parent_edge_bwd[v] <- graph$bwd_edge_ids[e_ptr]
            pq_bwd$push(as.character(v), new_cost)

            if (!is.infinite(dist_fwd[v])) {
              cand_cost <- dist_fwd[v] + new_cost
              if (cand_cost < best_cost) {
                best_cost <- cand_cost
                meet_node <- v
              }
            }
          }
        }
      }
    }
  }

  if (is.infinite(best_cost) || meet_node == 0L) {
    return(polaris_route_result(
      nodes = character(0),
      edges = character(0),
      total_distance = Inf,
      total_time = Inf,
      algorithm = "bidirectional_dijkstra",
      status = "NO_PATH_FOUND"
    ))
  }

  # Reconstruct path through meeting node
  # 1. Forward segment s -> meet_node
  fwd_nodes <- integer(0)
  fwd_edges <- character(0)
  curr <- meet_node
  while (curr != 0L && curr != s_idx) {
    fwd_nodes <- c(curr, fwd_nodes)
    fwd_edges <- c(parent_edge_fwd[curr], fwd_edges)
    curr <- parent_node_fwd[curr]
  }
  fwd_nodes <- c(s_idx, fwd_nodes)

  # 2. Backward segment meet_node -> t
  bwd_nodes <- integer(0)
  bwd_edges <- character(0)
  curr <- meet_node
  while (curr != 0L && curr != t_idx) {
    next_node <- parent_node_bwd[curr]
    bwd_nodes <- c(bwd_nodes, next_node)
    bwd_edges <- c(bwd_edges, parent_edge_bwd[curr])
    curr <- next_node
  }

  total_nodes_idx <- c(fwd_nodes, bwd_nodes)
  total_edges <- c(fwd_edges, bwd_edges)
  total_node_ids <- graph$idx_to_node[total_nodes_idx]

  # Calculate metrics and geometry
  tot_dist <- 0.0
  tot_time <- 0.0
  geom_list <- list()

  for (e_id in total_edges) {
    edge_obj <- graph$get_edge(e_id)
    if (!is.null(edge_obj)) {
      tot_dist <- tot_dist + edge_obj$distance
      tot_time <- tot_time + edge_obj$travel_time
    }
  }
  for (nd_id in total_node_ids) {
    geom_list[[length(geom_list) + 1L]] <- graph$node_coords[[nd_id]]
  }

  polaris_route_result(
    nodes = total_node_ids,
    edges = total_edges,
    total_distance = tot_dist,
    total_time = tot_time,
    geometry = geom_list,
    algorithm = "bidirectional_dijkstra",
    status = "OK"
  )
}
