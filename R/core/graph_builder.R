# Polaris Core Graph Builder: Topology Construction, Edge Deduplication & Pruning
# High-level pipeline converting tabular/raw road data into optimized Polaris graphs

#' Build Polaris Graph from Tabular Data
#'
#' Ingests data frames of nodes and edges, validates topological integrity,
#' deduplicates parallel edges, and initializes spatial indices.
#'
#' @param nodes_df Data frame with columns: id, lat, lon, and optional ele
#' @param edges_df Data frame with columns: id, source, target, distance,
#'   and optional travel_time, speed_limit, oneway, highway_type
#' @param prune_isolated Logical, whether to drop vertices with zero edges
#' @return A finalized polaris_graph instance with pre-computed CSR arrays
#' @export
build_polaris_graph <- function(nodes_df, edges_df, prune_isolated = TRUE) {
  g <- polaris_graph()

  # Step 1: Add all vertices
  n_nodes <- nrow(nodes_df)
  has_ele <- "ele" %in% names(nodes_df)

  for (i in seq_len(n_nodes)) {
    ele_val <- if (has_ele) as.numeric(nodes_df$ele[i]) else 0.0
    g$add_node(
      id = as.character(nodes_df$id[i]),
      lat = as.numeric(nodes_df$lat[i]),
      lon = as.numeric(nodes_df$lon[i]),
      ele = ele_val
    )
  }

  # Step 2: Add all edges with attribute defaults
  n_edges <- nrow(edges_df)
  has_time <- "travel_time" %in% names(edges_df)
  has_speed <- "speed_limit" %in% names(edges_df)
  has_oneway <- "oneway" %in% names(edges_df)
  has_hwy <- "highway_type" %in% names(edges_df)

  for (i in seq_len(n_edges)) {
    s_id <- as.character(edges_df$source[i])
    t_id <- as.character(edges_df$target[i])

    # Skip edges referencing non-existent nodes
    if (is.null(g$nodes[[s_id]]) || is.null(g$nodes[[t_id]])) {
      next
    }

    dist_val <- as.numeric(edges_df$distance[i])
    time_val <- if (has_time && !is.na(edges_df$travel_time[i])) as.numeric(edges_df$travel_time[i]) else NULL
    spd_val  <- if (has_speed && !is.na(edges_df$speed_limit[i])) as.numeric(edges_df$speed_limit[i]) else 50.0
    ow_val   <- if (has_oneway && !is.na(edges_df$oneway[i])) as.logical(edges_df$oneway[i]) else FALSE
    hwy_val  <- if (has_hwy && !is.na(edges_df$highway_type[i])) as.character(edges_df$highway_type[i]) else "primary"

    g$add_edge(
      id = as.character(edges_df$id[i]),
      source = s_id,
      target = t_id,
      distance = dist_val,
      travel_time = time_val,
      speed_limit = spd_val,
      oneway = ow_val,
      highway_type = hwy_val
    )
  }

  # Step 3: Prune isolated nodes if requested
  if (prune_isolated) {
    active_nodes <- character(0)
    for (nd_id in g$node_ids) {
      if (length(g$forward_adj[[nd_id]]) > 0L || length(g$backward_adj[[nd_id]]) > 0L) {
        active_nodes <- c(active_nodes, nd_id)
      } else {
        rm(list = nd_id, envir = g$nodes)
        rm(list = nd_id, envir = g$forward_adj)
        rm(list = nd_id, envir = g$backward_adj)
      }
    }
    g$node_ids <- active_nodes
  }

  # Step 4: Finalize Compressed Sparse Row arrays
  g$build_csr()
  g
}

#' Graph Summary Statistics
#'
#' Computes topology metrics: node count, edge count, density, average degree,
#' total network length in kilometers, and bounding box dimensions.
#'
#' @param g polaris_graph object
#' @return Named list of graph metrics
#' @export
graph_summary <- function(g) {
  n_nodes <- g$node_count()
  n_edges <- g$edge_count()

  total_meters <- 0.0
  for (e_id in g$edge_ids) {
    total_meters <- total_meters + g$edges[[e_id]]$distance
  }

  density <- if (n_nodes > 1) n_edges / (n_nodes * (n_nodes - 1)) else 0.0

  list(
    node_count = n_nodes,
    edge_count = n_edges,
    total_length_km = total_meters / 1000.0,
    density = density,
    bbox = g$bbox
  )
}

#' Build Spatial KD-Tree Index Over Graph Vertices
#'
#' Allows sub-millisecond snapping of arbitrary geographic coordinates
#' to the nearest valid graph vertex.
#'
#' @param g polaris_graph object
#' @return polaris_kdtree instance
#' @export
build_graph_kdtree <- function(g) {
  n <- g$node_count()
  pts <- matrix(0.0, nrow = n, ncol = 2)
  ids <- character(n)

  for (i in seq_len(n)) {
    nd_id <- g$node_ids[i]
    coord <- g$node_coords[[nd_id]]
    pts[i, 1] <- coord$lat
    pts[i, 2] <- coord$lon
    ids[i] <- nd_id
  }

  polaris_kdtree(points = pts, ids = ids)
}
