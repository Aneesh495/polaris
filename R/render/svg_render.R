# Polaris Render: Standalone SVG Vector Map Exporter
# Generates high-fidelity SVG graphics of road topologies, routes, and isochrones

#' Export Network Graph and Route to Standalone SVG
#'
#' @param graph Base polaris_graph object
#' @param output_file File path ending in .svg
#' @param route_result Optional polaris_route_result to highlight
#' @param isochrone_poly Optional data frame of isochrone boundary (lat, lon)
#' @param width SVG width in pixels (default 800)
#' @param height SVG height in pixels (default 600)
#' @export
export_svg_map <- function(graph, output_file,
                           route_result = NULL,
                           isochrone_poly = NULL,
                           width = 800L, height = 600L) {
  bbox <- graph$bbox
  if (is.null(bbox)) {
    stop("export_svg_map: graph has no nodes to render")
  }

  margin <- 40.0
  draw_w <- width - 2.0 * margin
  draw_h <- height - 2.0 * margin

  lat_span <- max(1e-6, bbox$max_lat - bbox$min_lat)
  lon_span <- max(1e-6, bbox$max_lon - bbox$min_lon)

  # Coordinate mapping to SVG pixels
  geo_to_svg <- function(lat, lon) {
    x <- margin + ((lon - bbox$min_lon) / lon_span) * draw_w
    y <- margin + ((bbox$max_lat - lat) / lat_span) * draw_h
    c(x = round(x, 2), y = round(y, 2))
  }

  svg_lines <- character(0)
  svg_lines <- c(svg_lines, sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">',
                                    width, height, width, height))

  # Background styling and definitions
  svg_lines <- c(svg_lines, '<defs>')
  svg_lines <- c(svg_lines, '  <style>')
  svg_lines <- c(svg_lines, '    .bg { fill: #1a1a24; }')
  svg_lines <- c(svg_lines, '    .road-motorway { stroke: #e67e22; stroke-width: 3.5; stroke-linecap: round; }')
  svg_lines <- c(svg_lines, '    .road-primary { stroke: #e74c3c; stroke-width: 2.5; stroke-linecap: round; }')
  svg_lines <- c(svg_lines, '    .road-secondary { stroke: #f39c12; stroke-width: 1.8; stroke-linecap: round; }')
  svg_lines <- c(svg_lines, '    .road-default { stroke: #4a4a5a; stroke-width: 1.2; stroke-linecap: round; }')
  svg_lines <- c(svg_lines, '    .node-dot { fill: #7f8c8d; }')
  svg_lines <- c(svg_lines, '    .route-path { stroke: #00d2d3; stroke-width: 4.5; fill: none; stroke-linecap: round; stroke-linejoin: round; }')
  svg_lines <- c(svg_lines, '    .isochrone-fill { fill: #9b59b6; fill-opacity: 0.25; stroke: #8e44ad; stroke-width: 2; stroke-dasharray: 4,4; }')
  svg_lines <- c(svg_lines, '    .marker-start { fill: #2ecc71; stroke: #ffffff; stroke-width: 2; }')
  svg_lines <- c(svg_lines, '    .marker-end { fill: #e74c3c; stroke: #ffffff; stroke-width: 2; }')
  svg_lines <- c(svg_lines, '    .label-text { font-family: monospace; font-size: 11px; fill: #ecf0f1; }')
  svg_lines <- c(svg_lines, '  </style>')
  svg_lines <- c(svg_lines, '</defs>')

  # Background rectangle
  svg_lines <- c(svg_lines, sprintf('<rect class="bg" width="%d" height="%d" rx="8"/>', width, height))

  # 1. Render Isochrone if present
  if (!is.null(isochrone_poly) && nrow(isochrone_poly) >= 3) {
    poly_pts <- character(nrow(isochrone_poly))
    for (i in seq_len(nrow(isochrone_poly))) {
      p <- geo_to_svg(isochrone_poly$lat[i], isochrone_poly$lon[i])
      poly_pts[i] <- sprintf("%.1f,%.1f", p["x"], p["y"])
    }
    svg_lines <- c(svg_lines, sprintf('<polygon class="isochrone-fill" points="%s"/>',
                                      paste(poly_pts, collapse = " ")))
  }

  # 2. Render Road Network Segments
  for (e_id in graph$edge_ids) {
    e <- graph$get_edge(e_id)
    u_c <- geo_to_svg(graph$node_coords[[e$source]]$lat, graph$node_coords[[e$source]]$lon)
    v_c <- geo_to_svg(graph$node_coords[[e$target]]$lat, graph$node_coords[[e$target]]$lon)

    cls <- switch(e$highway_type,
      "motorway" = "road-motorway",
      "primary" = "road-primary",
      "secondary" = "road-secondary",
      "road-default"
    )

    svg_lines <- c(svg_lines, sprintf('<line class="%s" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
                                      cls, u_c["x"], u_c["y"], v_c["x"], v_c["y"]))
  }

  # 3. Render Vertices
  for (nd_id in graph$node_ids) {
    coord <- graph$node_coords[[nd_id]]
    p <- geo_to_svg(coord$lat, coord$lon)
    svg_lines <- c(svg_lines, sprintf('<circle class="node-dot" cx="%.1f" cy="%.1f" r="2.0"/>', p["x"], p["y"]))
  }

  # 4. Render Route if present
  if (!is.null(route_result) && length(route_result$nodes) > 1L) {
    r_nodes <- route_result$nodes
    pts_str <- character(length(r_nodes))
    for (i in seq_along(r_nodes)) {
      p <- geo_to_svg(graph$node_coords[[r_nodes[i]]]$lat, graph$node_coords[[r_nodes[i]]]$lon)
      pts_str[i] <- sprintf("%.1f,%.1f", p["x"], p["y"])
    }
    svg_lines <- c(svg_lines, sprintf('<polyline class="route-path" points="%s"/>',
                                      paste(pts_str, collapse = " ")))

    # Start and End Markers
    s_p <- geo_to_svg(graph$node_coords[[r_nodes[1L]]]$lat, graph$node_coords[[r_nodes[1L]]]$lon)
    t_p <- geo_to_svg(graph$node_coords[[r_nodes[length(r_nodes)]]]$lat, graph$node_coords[[r_nodes[length(r_nodes)]]]$lon)

    svg_lines <- c(svg_lines, sprintf('<circle class="marker-start" cx="%.1f" cy="%.1f" r="6.0"/>', s_p["x"], s_p["y"]))
    svg_lines <- c(svg_lines, sprintf('<circle class="marker-end" cx="%.1f" cy="%.1f" r="6.0"/>', t_p["x"], t_p["y"]))

    # Info overlay
    info_text <- sprintf("Distance: %.2f km | Time: %.1f min | Algo: %s",
                         route_result$total_distance / 1000.0,
                         route_result$total_time / 60.0,
                         route_result$algorithm)
    svg_lines <- c(svg_lines, sprintf('<text class="label-text" x="20" y="%d">%s</text>', height - 15, info_text))
  }

  # Header watermark
  svg_lines <- c(svg_lines, '<text class="label-text" x="20" y="25">Polaris High-Performance Spatial Routing Engine</text>')
  svg_lines <- c(svg_lines, '</svg>')

  writeLines(svg_lines, con = output_file, useBytes = TRUE)
  cat(sprintf("[polaris-render] Exported SVG map to %s (%d bytes)\n", output_file, file.info(output_file)$size))
  invisible(output_file)
}
