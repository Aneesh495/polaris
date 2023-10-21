# Polaris Render: ANSI Terminal Color Map Visualizer
# Projects graph topologies and path trajectories onto 2D ASCII/ANSI text viewports

#' Render Routing Path and Graph Topology in Terminal
#'
#' @param graph Base polaris_graph object
#' @param route_result Optional polaris_route_result to highlight
#' @param width Terminal columns (default 70)
#' @param height Terminal rows (default 22)
#' @return Character vector of rendered lines (also printed to console)
#' @export
render_terminal_map <- function(graph, route_result = NULL, width = 70L, height = 22L) {
  bbox <- graph$bbox
  if (is.null(bbox)) {
    cat("[polaris-render] Graph has no nodes to render.\n")
    return(character(0))
  }

  lat_span <- max(1e-6, bbox$max_lat - bbox$min_lat)
  lon_span <- max(1e-6, bbox$max_lon - bbox$min_lon)

  # Map projection to character cell (1 to height, 1 to width)
  # Row 1 is top (max_lat), Row height is bottom (min_lat)
  geo_to_cell <- function(lat, lon) {
    r <- as.integer(round((bbox$max_lat - lat) / lat_span * (height - 1L))) + 1L
    c <- as.integer(round((lon - bbox$min_lon) / lon_span * (width - 1L))) + 1L
    c(r = max(1L, min(height, r)), c = max(1L, min(width, c)))
  }

  # Canvas initialization
  canvas <- matrix(" ", nrow = height, ncol = width)

  # 1. Draw road segments as subtle dots/lines
  for (e_id in graph$edge_ids) {
    e <- graph$get_edge(e_id)
    c1 <- geo_to_cell(graph$node_coords[[e$source]]$lat, graph$node_coords[[e$source]]$lon)
    c2 <- geo_to_cell(graph$node_coords[[e$target]]$lat, graph$node_coords[[e$target]]$lon)

    # Simple Bresenham line plotting on character grid
    r0 <- c1["r"]; c0 <- c1["c"]
    r1 <- c2["r"]; c1_c <- c2["c"]

    dr <- abs(r1 - r0)
    dc <- abs(c1_c - c0)
    sr <- if (r0 < r1) 1L else -1L
    sc <- if (c0 < c1_c) 1L else -1L
    err <- (if (dc > dr) dc else -dr) / 2L

    cur_r <- r0
    cur_c <- c0
    while (TRUE) {
      if (canvas[cur_r, cur_c] == " ") {
        canvas[cur_r, cur_c] <- "."
      }
      if (cur_r == r1 && cur_c == c1_c) break
      e2 <- err
      if (e2 > -dc) { err <- err - dr; cur_c <- cur_c + sc }
      if (e2 < dr)  { err <- err + dc; cur_r <- cur_r + sr }
    }
  }

  # 2. Draw vertices
  for (nd_id in graph$node_ids) {
    coord <- graph$node_coords[[nd_id]]
    pos <- geo_to_cell(coord$lat, coord$lon)
    canvas[pos["r"], pos["c"]] <- "+"
  }

  # 3. Highlight route if provided
  if (!is.null(route_result) && length(route_result$nodes) > 1L) {
    r_nodes <- route_result$nodes
    for (i in seq_len(length(r_nodes) - 1L)) {
      u_c <- geo_to_cell(graph$node_coords[[r_nodes[i]]]$lat, graph$node_coords[[r_nodes[i]]]$lon)
      v_c <- geo_to_cell(graph$node_coords[[r_nodes[i + 1L]]]$lat, graph$node_coords[[r_nodes[i + 1L]]]$lon)

      # Bresenham on route
      r0 <- u_c["r"]; c0 <- u_c["c"]
      r1 <- v_c["r"]; c1_c <- v_c["c"]
      dr <- abs(r1 - r0)
      dc <- abs(c1_c - c0)
      sr <- if (r0 < r1) 1L else -1L
      sc <- if (c0 < c1_c) 1L else -1L
      err <- (if (dc > dr) dc else -dr) / 2L
      cur_r <- r0; cur_c <- c0
      while (TRUE) {
        canvas[cur_r, cur_c] <- "#"
        if (cur_r == r1 && cur_c == c1_c) break
        e2 <- err
        if (e2 > -dc) { err <- err - dr; cur_c <- cur_c + sc }
        if (e2 < dr)  { err <- err + dc; cur_r <- cur_r + sr }
      }
    }
    # Mark Origin and Destination
    orig_pos <- geo_to_cell(graph$node_coords[[r_nodes[1L]]]$lat, graph$node_coords[[r_nodes[1L]]]$lon)
    dest_pos <- geo_to_cell(graph$node_coords[[r_nodes[length(r_nodes)]]]$lat, graph$node_coords[[r_nodes[length(r_nodes)]]]$lon)
    canvas[orig_pos["r"], orig_pos["c"]] <- "S" # Start
    canvas[dest_pos["r"], dest_pos["c"]] <- "T" # Target
  }

  # Build header and border
  border_top <- paste0("+", paste0(rep("-", width), collapse = ""), "+")
  rendered_lines <- character(height + 2L)
  rendered_lines[1L] <- border_top
  for (r in seq_len(height)) {
    rendered_lines[r + 1L] <- paste0("|", paste0(canvas[r, ], collapse = ""), "|")
  }
  rendered_lines[height + 2L] <- border_top

  # Output to console
  cat(paste(rendered_lines, collapse = "\n"), "\n")
  invisible(rendered_lines)
}
