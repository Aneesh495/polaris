# Polaris Core Graph: Adjacency Representations, CSR Flat Storage, and SCC Analysis
# High-throughput graph topology foundation for bidirectional routing and contraction

#' Polaris Routing Graph
#'
#' Encapsulates network nodes, directed edges, dual-direction adjacency lists,
#' and CSR (Compressed Sparse Row) flat arrays for maximum relaxation efficiency.
#'
#' @return An environment-based mutable graph object of class polaris_graph
#' @export
polaris_graph <- function() {
  g <- new.env(parent = emptyenv())

  # Node registries
  g$nodes <- new.env(hash = TRUE, parent = emptyenv())
  g$node_ids <- character(0)
  g$node_coords <- list() # id -> polaris_coordinate

  # Edge registries
  g$edges <- new.env(hash = TRUE, parent = emptyenv())
  g$edge_ids <- character(0)

  # Adjacency lists: node_id -> list of outgoing/incoming edge objects
  g$forward_adj <- new.env(hash = TRUE, parent = emptyenv())
  g$backward_adj <- new.env(hash = TRUE, parent = emptyenv())

  # CSR arrays (built on finalize)
  g$csr_built <- FALSE
  g$node_to_idx <- new.env(hash = TRUE, parent = emptyenv()) # node_id -> integer index
  g$idx_to_node <- character(0)
  g$fwd_offsets <- integer(0)
  g$fwd_targets <- integer(0)
  g$fwd_weights <- numeric(0)
  g$fwd_times <- numeric(0)
  g$fwd_edge_ids <- character(0)

  g$bwd_offsets <- integer(0)
  g$bwd_targets <- integer(0)
  g$bwd_weights <- numeric(0)
  g$bwd_times <- numeric(0)
  g$bwd_edge_ids <- character(0)

  # Bounding box
  g$bbox <- NULL

  # Add node
  g$add_node <- function(id, lat, lon, ele = 0.0, tags = list()) {
    node_id <- as.character(id)
    if (!is.null(g$nodes[[node_id]])) {
      return(invisible(node_id))
    }
    nd <- polaris_node(node_id, lat, lon, ele, tags)
    g$nodes[[node_id]] <- nd
    g$node_ids <- c(g$node_ids, node_id)
    g$node_coords[[node_id]] <- nd$coord
    g$forward_adj[[node_id]] <- list()
    g$backward_adj[[node_id]] <- list()

    # Update bounding box
    if (is.null(g$bbox)) {
      g$bbox <- polaris_bbox(lat, lon, lat, lon)
    } else {
      g$bbox <- bbox_expand(g$bbox, nd$coord)
    }
    g$csr_built <- FALSE
    invisible(node_id)
  }

  # Add directed edge
  g$add_edge <- function(id, source, target, distance, travel_time = NULL,
                         speed_limit = 50.0, oneway = FALSE,
                         highway_type = "primary", geometry = list()) {
    e_id <- as.character(id)
    s_id <- as.character(source)
    t_id <- as.character(target)

    if (is.null(g$nodes[[s_id]])) {
      stop(sprintf("add_edge: source node '%s' does not exist in graph", s_id))
    }
    if (is.null(g$nodes[[t_id]])) {
      stop(sprintf("add_edge: target node '%s' does not exist in graph", t_id))
    }

    edge_obj <- polaris_edge(
      id = e_id,
      source = s_id,
      target = t_id,
      distance = distance,
      travel_time = travel_time,
      speed_limit = speed_limit,
      oneway = oneway,
      highway_type = highway_type,
      geometry = geometry
    )

    g$edges[[e_id]] <- edge_obj
    g$edge_ids <- c(g$edge_ids, e_id)

    # Insert into forward adjacency
    f_list <- g$forward_adj[[s_id]]
    f_list[[length(f_list) + 1L]] <- edge_obj
    g$forward_adj[[s_id]] <- f_list

    # Insert into backward adjacency
    b_list <- g$backward_adj[[t_id]]
    b_list[[length(b_list) + 1L]] <- edge_obj
    g$backward_adj[[t_id]] <- b_list

    # If edge is bidirectional (oneway == FALSE), add reverse edge
    if (!oneway) {
      rev_e_id <- paste0(e_id, "_rev")
      rev_edge_obj <- polaris_edge(
        id = rev_e_id,
        source = t_id,
        target = s_id,
        distance = distance,
        travel_time = travel_time,
        speed_limit = speed_limit,
        oneway = TRUE,
        highway_type = highway_type,
        geometry = if (length(geometry) > 0) rev(geometry) else list()
      )
      g$edges[[rev_e_id]] <- rev_edge_obj
      g$edge_ids <- c(g$edge_ids, rev_e_id)

      f_rev <- g$forward_adj[[t_id]]
      f_rev[[length(f_rev) + 1L]] <- rev_edge_obj
      g$forward_adj[[t_id]] <- f_rev

      b_rev <- g$backward_adj[[s_id]]
      b_rev[[length(b_rev) + 1L]] <- rev_edge_obj
      g$backward_adj[[s_id]] <- b_rev
    }

    g$csr_built <- FALSE
    invisible(e_id)
  }

  # Build Compressed Sparse Row arrays
  g$build_csr <- function() {
    n_nodes <- length(g$node_ids)
    g$idx_to_node <- g$node_ids
    rm(list = ls(envir = g$node_to_idx), envir = g$node_to_idx)
    for (i in seq_len(n_nodes)) {
      g$node_to_idx[[g$node_ids[i]]] <- i
    }

    # Count edges
    fwd_counts <- integer(n_nodes)
    bwd_counts <- integer(n_nodes)
    for (i in seq_len(n_nodes)) {
      u_id <- g$node_ids[i]
      fwd_counts[i] <- length(g$forward_adj[[u_id]])
      bwd_counts[i] <- length(g$backward_adj[[u_id]])
    }

    total_fwd <- sum(fwd_counts)
    total_bwd <- sum(bwd_counts)

    # Allocate CSR vectors
    g$fwd_offsets <- integer(n_nodes + 1L)
    g$fwd_targets <- integer(total_fwd)
    g$fwd_weights <- numeric(total_fwd)
    g$fwd_times <- numeric(total_fwd)
    g$fwd_edge_ids <- character(total_fwd)

    g$bwd_offsets <- integer(n_nodes + 1L)
    g$bwd_targets <- integer(total_bwd)
    g$bwd_weights <- numeric(total_bwd)
    g$bwd_times <- numeric(total_bwd)
    g$bwd_edge_ids <- character(total_bwd)

    # Populate forward CSR
    fwd_ptr <- 1L
    g$fwd_offsets[1L] <- 1L
    for (i in seq_len(n_nodes)) {
      u_id <- g$node_ids[i]
      edges <- g$forward_adj[[u_id]]
      for (e in edges) {
        v_idx <- g$node_to_idx[[e$target]]
        g$fwd_targets[fwd_ptr] <- v_idx
        g$fwd_weights[fwd_ptr] <- e$distance
        g$fwd_times[fwd_ptr] <- e$travel_time
        g$fwd_edge_ids[fwd_ptr] <- e$id
        fwd_ptr <- fwd_ptr + 1L
      }
      g$fwd_offsets[i + 1L] <- fwd_ptr
    }

    # Populate backward CSR
    bwd_ptr <- 1L
    g$bwd_offsets[1L] <- 1L
    for (i in seq_len(n_nodes)) {
      u_id <- g$node_ids[i]
      edges <- g$backward_adj[[u_id]]
      for (e in edges) {
        v_idx <- g$node_to_idx[[e$source]]
        g$bwd_targets[bwd_ptr] <- v_idx
        g$bwd_weights[bwd_ptr] <- e$distance
        g$bwd_times[bwd_ptr] <- e$travel_time
        g$bwd_edge_ids[bwd_ptr] <- e$id
        bwd_ptr <- bwd_ptr + 1L
      }
      g$bwd_offsets[i + 1L] <- bwd_ptr
    }

    g$csr_built <- TRUE
    invisible(NULL)
  }

  # Node count
  g$node_count <- function() {
    length(g$node_ids)
  }

  # Edge count
  g$edge_count <- function() {
    length(g$edge_ids)
  }

  # Get node object
  g$get_node <- function(id) {
    g$nodes[[as.character(id)]]
  }

  # Get edge object
  g$get_edge <- function(id) {
    g$edges[[as.character(id)]]
  }

  # Out-degree
  g$out_degree <- function(id) {
    length(g$forward_adj[[as.character(id)]])
  }

  # In-degree
  g$in_degree <- function(id) {
    length(g$backward_adj[[as.character(id)]])
  }

  # Tarjan Strongly Connected Components (SCC)
  g$tarjan_scc <- function() {
    if (!g$csr_built) g$build_csr()
    n <- g$node_count()
    if (n == 0L) return(list())

    index_val <- 0L
    indices <- integer(n) # 0 means unvisited
    lowlinks <- integer(n)
    on_stack <- logical(n)
    stack <- integer(n)
    stack_ptr <- 0L
    sccs <- list()

    strong_connect <- function(v) {
      index_val <<- index_val + 1L
      indices[v] <<- index_val
      lowlinks[v] <<- index_val
      stack_ptr <<- stack_ptr + 1L
      stack[stack_ptr] <<- v
      on_stack[v] <<- TRUE

      start_edge <- g$fwd_offsets[v]
      end_edge <- g$fwd_offsets[v + 1L] - 1L

      if (start_edge <= end_edge) {
        for (e_idx in start_edge:end_edge) {
          w <- g$fwd_targets[e_idx]
          if (indices[w] == 0L) {
            strong_connect(w)
            lowlinks[v] <<- min(lowlinks[v], lowlinks[w])
          } else if (on_stack[w]) {
            lowlinks[v] <<- min(lowlinks[v], indices[w])
          }
        }
      }

      if (lowlinks[v] == indices[v]) {
        comp <- character(0)
        while (TRUE) {
          w <- stack[stack_ptr]
          stack_ptr <<- stack_ptr - 1L
          on_stack[w] <<- FALSE
          comp <- c(comp, g$idx_to_node[w])
          if (w == v) break
        }
        sccs[[length(sccs) + 1L]] <<- comp
      }
    }

    for (i in seq_len(n)) {
      if (indices[i] == 0L) {
        strong_connect(i)
      }
    }

    sccs
  }

  # Extract largest strongly connected component
  g$largest_scc_subgraph <- function() {
    sccs <- g$tarjan_scc()
    if (length(sccs) == 0L) return(polaris_graph())

    lens <- vapply(sccs, length, integer(1))
    largest_nodes <- sccs[[which.max(lens)]]
    valid_set <- new.env(hash = TRUE, parent = emptyenv(), size = length(largest_nodes))
    for (nd in largest_nodes) valid_set[[nd]] <- TRUE

    sub_g <- polaris_graph()
    for (nd_id in largest_nodes) {
      nd <- g$get_node(nd_id)
      sub_g$add_node(nd$id, nd$coord$lat, nd$coord$lon, nd$coord$ele, nd$tags)
    }

    for (e_id in g$edge_ids) {
      e <- g$get_edge(e_id)
      if (!is.null(valid_set[[e$source]]) && !is.null(valid_set[[e$target]])) {
        sub_g$add_edge(
          id = e$id,
          source = e$source,
          target = e$target,
          distance = e$distance,
          travel_time = e$travel_time,
          speed_limit = e$speed_limit,
          oneway = TRUE, # preserve exact directionality
          highway_type = e$highway_type,
          geometry = e$geometry
        )
      }
    }
    sub_g$build_csr()
    sub_g
  }

  structure(g, class = "polaris_graph")
}
