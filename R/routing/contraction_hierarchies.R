# Polaris Routing Engine: Contraction Hierarchies (CH) Preprocessor & Query
# Upward graph contraction, witness search, shortcut synthesis, and microsecond queries

#' Shortcut Edge Definition for Contraction Hierarchies
#'
#' @param id Unique shortcut identifier
#' @param source Origin vertex ID
#' @param target Destination vertex ID
#' @param distance Geometric length in meters
#' @param travel_time Travel duration in seconds
#' @param bypassed_node Contracted intermediate node
#' @param edge1 Incoming edge identifier to contracted node
#' @param edge2 Outgoing edge identifier from contracted node
#' @export
polaris_shortcut <- function(id, source, target, distance, travel_time,
                             bypassed_node, edge1, edge2) {
  structure(
    list(
      id = as.character(id),
      source = as.character(source),
      target = as.character(target),
      distance = as.numeric(distance),
      travel_time = as.numeric(travel_time),
      bypassed_node = as.character(bypassed_node),
      edge1 = as.character(edge1),
      edge2 = as.character(edge2),
      is_shortcut = TRUE
    ),
    class = "polaris_shortcut"
  )
}

#' Contraction Hierarchies Preprocessor
#'
#' Contracts vertices in priority order, inserting shortcuts when no witness path exists.
#' Produces an upward hierarchy graph enabling sub-millisecond bidirectional query answering.
#'
#' @param graph Base polaris_graph object
#' @param metric Minimization metric: 'distance' (meters) or 'time' (seconds)
#' @param max_witness_hops Maximum hops for localized witness search (default 5)
#' @return An environment of class polaris_ch_index
#' @export
ch_preprocess <- function(graph, metric = "distance", max_witness_hops = 5L) {
  if (!graph$csr_built) graph$build_csr()
  n <- graph$node_count()
  use_time <- (metric == "time")

  cat(sprintf("[polaris-ch] Preprocessing Contraction Hierarchies (%d vertices, metric=%s)...\n", n, metric))

  # Active status of nodes (uncontracted = TRUE, contracted = FALSE)
  is_active <- rep(TRUE, n)
  node_ranks <- integer(n)
  contracted_neighbors <- integer(n)

  # Adjacency maps for contraction (modified as shortcuts are added)
  # Store list of edge records: list(target, weight, time, id, is_shortcut, edge1, edge2, bypassed)
  fwd_edges <- vector("list", n)
  bwd_edges <- vector("list", n)

  for (u in seq_len(n)) {
    # Forward edges
    s_f <- graph$fwd_offsets[u]
    e_f <- graph$fwd_offsets[u + 1L] - 1L
    if (s_f <= e_f) {
      for (ptr in s_f:e_f) {
        v <- graph$fwd_targets[ptr]
        fwd_edges[[u]][[length(fwd_edges[[u]]) + 1L]] <- list(
          target = v,
          weight = graph$fwd_weights[ptr],
          time = graph$fwd_times[ptr],
          id = graph$fwd_edge_ids[ptr],
          is_shortcut = FALSE,
          bypassed = NA_character_,
          edge1 = NA_character_,
          edge2 = NA_character_
        )
      }
    }
    # Backward edges
    s_b <- graph$bwd_offsets[u]
    e_b <- graph$bwd_offsets[u + 1L] - 1L
    if (s_b <= e_b) {
      for (ptr in s_b:e_b) {
        v <- graph$bwd_targets[ptr]
        bwd_edges[[u]][[length(bwd_edges[[u]]) + 1L]] <- list(
          target = v,
          weight = graph$bwd_weights[ptr],
          time = graph$bwd_times[ptr],
          id = graph$bwd_edge_ids[ptr],
          is_shortcut = FALSE,
          bypassed = NA_character_,
          edge1 = NA_character_,
          edge2 = NA_character_
        )
      }
    }
  }

  # Localized witness search from u to w excluding v
  find_witness <- function(u, w, v, max_cost) {
    pq_w <- polaris_indexed_pq(initial_capacity = 32L)
    dist_w <- new.env(hash = TRUE, parent = emptyenv())
    hops_w <- new.env(hash = TRUE, parent = emptyenv())

    dist_w[[as.character(u)]] <- 0.0
    hops_w[[as.character(u)]] <- 0L
    pq_w$push(as.character(u), 0.0)

    while (!pq_w$is_empty()) {
      top <- pq_w$pop()
      curr <- as.integer(top$element)
      c_cost <- top$priority

      if (c_cost > max_cost) break
      if (curr == w) return(TRUE) # Witness found

      curr_hops <- hops_w[[as.character(curr)]]
      if (curr_hops >= max_witness_hops) next

      # Explore active uncontracted neighbors
      for (edge in fwd_edges[[curr]]) {
        nbr <- edge$target
        if (nbr == v || !is_active[nbr]) next

        edge_c <- if (use_time) edge$time else edge$weight
        nxt_cost <- c_cost + edge_c
        if (nxt_cost > max_cost) next

        old_c <- dist_w[[as.character(nbr)]]
        if (is.null(old_c) || nxt_cost < old_c) {
          dist_w[[as.character(nbr)]] <- nxt_cost
          hops_w[[as.character(nbr)]] <- curr_hops + 1L
          pq_w$push(as.character(nbr), nxt_cost)
        }
      }
    }
    FALSE
  }

  # Calculate contraction priority for node v
  compute_priority <- function(v) {
    in_edges <- bwd_edges[[v]]
    out_edges <- fwd_edges[[v]]

    # Filter active
    in_active <- Filter(function(e) is_active[e$target], in_edges)
    out_active <- Filter(function(e) is_active[e$target], out_edges)

    shortcuts_needed <- 0L
    for (in_e in in_active) {
      u <- in_e$target
      cost1 <- if (use_time) in_e$time else in_e$weight
      for (out_e in out_active) {
        w <- out_e$target
        if (u == w) next
        cost2 <- if (use_time) out_e$time else out_e$weight
        total_cand <- cost1 + cost2

        # Check if witness exists
        has_witness <- find_witness(u, w, v, total_cand)
        if (!has_witness) {
          shortcuts_needed <- shortcuts_needed + 1L
        }
      }
    }

    edge_difference <- shortcuts_needed - (length(in_active) + length(out_active))
    edge_difference + contracted_neighbors[v]
  }

  # Priority queue for lazy contraction ordering
  order_pq <- polaris_indexed_pq(initial_capacity = min(1024L, n))
  for (i in seq_len(n)) {
    order_pq$push(as.character(i), compute_priority(i))
  }

  shortcut_registry <- new.env(hash = TRUE, parent = emptyenv())
  shortcut_counter <- 0L
  current_rank <- 1L

  # Main contraction loop
  while (!order_pq$is_empty()) {
    top <- order_pq$pop()
    v <- as.integer(top$element)

    # Lazy priority check
    if (!order_pq$is_empty()) {
      new_prio <- compute_priority(v)
      if (new_prio > order_pq$peek()$priority) {
        order_pq$push(as.character(v), new_prio)
        next
      }
    }

    # Contract node v
    node_ranks[v] <- current_rank
    is_active[v] <- FALSE
    v_id <- graph$idx_to_node[v]

    in_active <- Filter(function(e) is_active[e$target], bwd_edges[[v]])
    out_active <- Filter(function(e) is_active[e$target], fwd_edges[[v]])

    # Insert necessary shortcuts
    for (in_e in in_active) {
      u <- in_e$target
      cost1 <- if (use_time) in_e$time else in_e$weight
      for (out_e in out_active) {
        w <- out_e$target
        if (u == w) next
        cost2 <- if (use_time) out_e$time else out_e$weight
        total_cand <- cost1 + cost2

        has_witness <- find_witness(u, w, v, total_cand)
        if (!has_witness) {
          shortcut_counter <- shortcut_counter + 1L
          sc_id <- sprintf("sc_%d_%d_%d", u, v, w)

          sc_dist <- in_e$weight + out_e$weight
          sc_time <- in_e$time + out_e$time

          sc_record <- list(
            target = w,
            weight = sc_dist,
            time = sc_time,
            id = sc_id,
            is_shortcut = TRUE,
            bypassed = v_id,
            edge1 = in_e$id,
            edge2 = out_e$id
          )

          fwd_edges[[u]][[length(fwd_edges[[u]]) + 1L]] <- sc_record
          bwd_edges[[w]][[length(bwd_edges[[w]]) + 1L]] <- list(
            target = u,
            weight = sc_dist,
            time = sc_time,
            id = sc_id,
            is_shortcut = TRUE,
            bypassed = v_id,
            edge1 = in_e$id,
            edge2 = out_e$id
          )

          shortcut_registry[[sc_id]] <- sc_record
        }
      }
    }

    # Increment contracted neighbor count for active neighbors
    for (in_e in in_active) {
      contracted_neighbors[in_e$target] <- contracted_neighbors[in_e$target] + 1L
    }
    for (out_e in out_active) {
      contracted_neighbors[out_e$target] <- contracted_neighbors[out_e$target] + 1L
    }

    current_rank <- current_rank + 1L
  }

  cat(sprintf("[polaris-ch] Contraction complete. Synthesized %d shortcuts.\n", shortcut_counter))

  # Build final Upward Forward and Upward Backward graphs
  upward_fwd <- vector("list", n)
  upward_bwd <- vector("list", n)

  for (u in seq_len(n)) {
    u_rank <- node_ranks[u]
    # Keep only forward edges to higher-rank targets
    for (e in fwd_edges[[u]]) {
      if (node_ranks[e$target] > u_rank) {
        upward_fwd[[u]][[length(upward_fwd[[u]]) + 1L]] <- e
      }
    }
    # Keep only backward edges to higher-rank sources
    for (e in bwd_edges[[u]]) {
      if (node_ranks[e$target] > u_rank) {
        upward_bwd[[u]][[length(upward_bwd[[u]]) + 1L]] <- e
      }
    }
  }

  ch_env <- new.env(parent = emptyenv())
  ch_env$graph <- graph
  ch_env$metric <- metric
  ch_env$node_ranks <- node_ranks
  ch_env$upward_fwd <- upward_fwd
  ch_env$upward_bwd <- upward_bwd
  ch_env$shortcuts <- shortcut_registry
  ch_env$shortcut_count <- shortcut_counter

  structure(ch_env, class = "polaris_ch_index")
}

#' Query Shortest Path on Contraction Hierarchies Upward Graph
#'
#' Evaluates shortest paths in sub-millisecond time by searching only upward graphs
#' and recursively unpacking shortcut edges into primitive network links.
#'
#' @param ch_index polaris_ch_index object from ch_preprocess()
#' @param source_id Origin vertex identifier
#' @param target_id Destination vertex identifier
#' @return polaris_route_result object
#' @export
polaris_ch_route <- function(ch_index, source_id, target_id) {
  g <- ch_index$graph
  s_str <- as.character(source_id)
  t_str <- as.character(target_id)
  s_idx <- g$node_to_idx[[s_str]]
  t_idx <- g$node_to_idx[[t_str]]

  if (is.null(s_idx)) stop(sprintf("ch_route: source '%s' not found", s_str))
  if (is.null(t_idx)) stop(sprintf("ch_route: target '%s' not found", t_str))

  if (s_idx == t_idx) {
    return(polaris_route_result(
      nodes = s_str,
      edges = character(0),
      total_distance = 0.0,
      total_time = 0.0,
      algorithm = "contraction_hierarchies",
      status = "OK"
    ))
  }

  n <- g$node_count()
  use_time <- (ch_index$metric == "time")

  dist_fwd <- rep(Inf, n)
  dist_bwd <- rep(Inf, n)
  parent_fwd <- vector("list", n) # list(node, edge_obj)
  parent_bwd <- vector("list", n)

  pq_fwd <- polaris_indexed_pq(initial_capacity = 256L)
  pq_bwd <- polaris_indexed_pq(initial_capacity = 256L)

  dist_fwd[s_idx] <- 0.0
  pq_fwd$push(as.character(s_idx), 0.0)

  dist_bwd[t_idx] <- 0.0
  pq_bwd$push(as.character(t_idx), 0.0)

  best_cost <- Inf
  meet_node <- 0L

  # Bidirectional upward search
  while (!pq_fwd$is_empty() || !pq_bwd$is_empty()) {
    min_fwd <- if (!pq_fwd$is_empty()) pq_fwd$peek()$priority else Inf
    min_bwd <- if (!pq_bwd$is_empty()) pq_bwd$peek()$priority else Inf

    if (min_fwd >= best_cost && min_bwd >= best_cost) {
      break
    }

    # Expand forward upward
    if (!pq_fwd$is_empty() && min_fwd <= min_bwd) {
      top <- pq_fwd$pop()
      u <- as.integer(top$element)
      u_cost <- top$priority

      if (u_cost > dist_fwd[u]) next

      if (!is.infinite(dist_bwd[u])) {
        c_cost <- u_cost + dist_bwd[u]
        if (c_cost < best_cost) {
          best_cost <- c_cost
          meet_node <- u
        }
      }

      for (edge in ch_index$upward_fwd[[u]]) {
        v <- edge$target
        c_edge <- if (use_time) edge$time else edge$weight
        new_c <- u_cost + c_edge
        if (new_c < dist_fwd[v]) {
          dist_fwd[v] <- new_c
          parent_fwd[[v]] <- list(node = u, edge = edge)
          pq_fwd$push(as.character(v), new_c)

          if (!is.infinite(dist_bwd[v])) {
            cand_total <- new_c + dist_bwd[v]
            if (cand_total < best_cost) {
              best_cost <- cand_total
              meet_node <- v
            }
          }
        }
      }
    } else if (!pq_bwd$is_empty()) {
      # Expand backward upward
      top <- pq_bwd$pop()
      u <- as.integer(top$element)
      u_cost <- top$priority

      if (u_cost > dist_bwd[u]) next

      if (!is.infinite(dist_fwd[u])) {
        c_cost <- u_cost + dist_fwd[u]
        if (c_cost < best_cost) {
          best_cost <- c_cost
          meet_node <- u
        }
      }

      for (edge in ch_index$upward_bwd[[u]]) {
        v <- edge$target
        c_edge <- if (use_time) edge$time else edge$weight
        new_c <- u_cost + c_edge
        if (new_c < dist_bwd[v]) {
          dist_bwd[v] <- new_c
          parent_bwd[[v]] <- list(node = u, edge = edge)
          pq_bwd$push(as.character(v), new_c)

          if (!is.infinite(dist_fwd[v])) {
            cand_total <- new_c + dist_fwd[v]
            if (cand_total < best_cost) {
              best_cost <- cand_total
              meet_node <- v
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
      algorithm = "contraction_hierarchies",
      status = "NO_PATH_FOUND"
    ))
  }

  # Recursive shortcut unpacker
  unpack_edge <- function(edge_record) {
    if (!edge_record$is_shortcut) {
      return(edge_record$id)
    }
    # Unpack edge1 and edge2
    e1_id <- edge_record$edge1
    e2_id <- edge_record$edge2

    e1_rec <- ch_index$shortcuts[[e1_id]]
    e2_rec <- ch_index$shortcuts[[e2_id]]

    unpacked1 <- if (!is.null(e1_rec)) unpack_edge(e1_rec) else e1_id
    unpacked2 <- if (!is.null(e2_rec)) unpack_edge(e2_rec) else e2_id

    c(unpacked1, unpacked2)
  }

  # Forward path reconstruction s -> meet_node
  fwd_edges_collected <- list()
  curr <- meet_node
  while (curr != s_idx) {
    p_info <- parent_fwd[[curr]]
    fwd_edges_collected <- c(list(p_info$edge), fwd_edges_collected)
    curr <- p_info$node
  }

  # Backward path reconstruction meet_node -> t
  bwd_edges_collected <- list()
  curr <- meet_node
  while (curr != t_idx) {
    p_info <- parent_bwd[[curr]]
    bwd_edges_collected <- c(bwd_edges_collected, list(p_info$edge))
    curr <- p_info$node
  }

  all_ch_edges <- c(fwd_edges_collected, bwd_edges_collected)
  primitive_edges <- character(0)

  for (e in all_ch_edges) {
    primitive_edges <- c(primitive_edges, unpack_edge(e))
  }

  # Reconstruct nodes from primitive edges
  if (length(primitive_edges) == 0L) {
    path_nodes <- c(s_str, t_str)
  } else {
    path_nodes <- character(length(primitive_edges) + 1L)
    path_nodes[1L] <- s_str
    for (i in seq_along(primitive_edges)) {
      e_obj <- g$get_edge(primitive_edges[i])
      path_nodes[i + 1L] <- if (!is.null(e_obj)) e_obj$target else ""
    }
  }

  # Summary metrics
  tot_dist <- 0.0
  tot_time <- 0.0
  geom_list <- list()

  for (e_id in primitive_edges) {
    edge_obj <- g$get_edge(e_id)
    if (!is.null(edge_obj)) {
      tot_dist <- tot_dist + edge_obj$distance
      tot_time <- tot_time + edge_obj$travel_time
    }
  }
  for (nd_id in path_nodes) {
    if (nd_id != "") {
      geom_list[[length(geom_list) + 1L]] <- g$node_coords[[nd_id]]
    }
  }

  polaris_route_result(
    nodes = path_nodes,
    edges = primitive_edges,
    total_distance = tot_dist,
    total_time = tot_time,
    geometry = geom_list,
    algorithm = "contraction_hierarchies",
    status = "OK"
  )
}
