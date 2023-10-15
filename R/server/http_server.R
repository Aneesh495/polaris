# Polaris HTTP Server: High-Performance Pure-R HTTP/1.1 REST Daemon
# Multi-path socket routing daemon providing RESTful JSON and GeoJSON APIs

#' Start Polaris HTTP/1.1 Daemon Server
#'
#' Binds a listening TCP socket, dispatching HTTP requests to routing, matching,
#' isochrone, and telemetry handlers.
#'
#' @param port Listening TCP port (default 8080)
#' @param graph Optional polaris_graph instance (synthesizes default network if NULL)
#' @param max_requests Maximum requests to serve before exiting (default Inf for daemon)
#' @export
polaris_start_server <- function(port = 8080L, graph = NULL, max_requests = Inf) {
  if (is.null(graph)) {
    # Create default demo network
    g <- polaris_graph()
    for (r in 1:6) {
      for (c in 1:6) {
        id <- sprintf("n_%d_%d", r, c)
        g$add_node(id, 37.75 + r * 0.01, -122.45 + c * 0.01)
      }
    }
    edge_idx <- 1L
    for (r in 1:6) {
      for (c in 1:5) {
        u <- sprintf("n_%d_%d", r, c)
        v <- sprintf("n_%d_%d", r, c + 1)
        d_m <- haversine_distance(g$node_coords[[u]]$lat, g$node_coords[[u]]$lon,
                                  g$node_coords[[v]]$lat, g$node_coords[[v]]$lon)
        g$add_edge(sprintf("e_h_%d", edge_idx), u, v, distance = d_m, speed_limit = 50.0, oneway = FALSE)
        edge_idx <- edge_idx + 1L
      }
    }
    for (r in 1:5) {
      for (c in 1:6) {
        u <- sprintf("n_%d_%d", r, c)
        v <- sprintf("n_%d_%d", r + 1, c)
        d_m <- haversine_distance(g$node_coords[[u]]$lat, g$node_coords[[u]]$lon,
                                  g$node_coords[[v]]$lat, g$node_coords[[v]]$lon)
        g$add_edge(sprintf("e_v_%d", edge_idx), u, v, distance = d_m, speed_limit = 45.0, oneway = FALSE)
        edge_idx <- edge_idx + 1L
      }
    }
    g$build_csr()
    graph <- g
  }

  cat(sprintf("[polaris-server] Binding TCP server socket on port %d...\n", port))
  server_sock <- tryCatch({
    serverSocket(port = as.integer(port))
  }, error = function(e) {
    stop(sprintf("Failed to bind socket on port %d: %s", port, e$message))
  })
  on.exit(close(server_sock))

  cat(sprintf("[polaris-server] Ready. Listening on http://127.0.0.1:%d/api/v1/health\n", port))
  request_count <- 0L

  while (request_count < max_requests) {
    conn <- socketAccept(server_sock, open = "r+b", blocking = TRUE)
    request_count <- request_count + 1L

    # Read request header line by line
    raw_req <- readLines(conn, n = 1L, warn = FALSE)
    if (length(raw_req) == 0L) {
      close(conn)
      next
    }

    req_parts <- strsplit(raw_req, " ")[[1]]
    if (length(req_parts) < 2L) {
      close(conn)
      next
    }

    method <- req_parts[1L]
    full_path <- req_parts[2L]
    path <- strsplit(full_path, "\\?")[[1]][1L]

    # Read remaining headers
    headers <- list()
    content_len <- 0L
    while (TRUE) {
      h_line <- readLines(conn, n = 1L, warn = FALSE)
      if (length(h_line) == 0L || h_line == "" || h_line == "\r") break
      if (grepl(":", h_line)) {
        parts <- strsplit(h_line, ":\\s*")[[1]]
        headers[[tolower(parts[1])]] <- parts[2]
      }
    }

    if (!is.null(headers[["content-length"]])) {
      content_len <- as.integer(headers[["content-length"]])
    }

    # Read body if present
    body_str <- ""
    if (content_len > 0L) {
      body_raw <- readChar(conn, nchars = content_len, useBytes = TRUE)
      body_str <- if (!is.na(body_raw)) body_raw else ""
    }

    # Handle endpoints
    response_body <- ""
    status_code <- "200 OK"

    if (path == "/api/v1/health") {
      accel_status <- is.loaded("c_dijkstra_csr")
      response_body <- sprintf(
        "{\"status\":\"UP\",\"engine\":\"polaris\",\"version\":\"0.1.0\",\"nodes\":%d,\"edges\":%d,\"accel_c\":%s,\"requests_served\":%d}",
        graph$node_count(), graph$edge_count(),
        if (accel_status) "true" else "false", request_count
      )
    } else if (path == "/api/v1/route") {
      # Route request: extract source and target
      # Simple parameter extraction or default
      s_id <- "n_1_1"
      t_id <- "n_6_6"
      if (grepl("source=([^&]+)", full_path)) {
        s_id <- sub(".*source=([^&]+).*", "\\1", full_path)
      }
      if (grepl("target=([^&]+)", full_path)) {
        t_id <- sub(".*target=([^&]+).*", "\\1", full_path)
      }

      res <- polaris_dijkstra(graph, source_id = s_id, target_id = t_id)
      response_body <- route_to_geojson(res)
    } else if (path == "/api/v1/isochrone") {
      s_id <- "n_1_1"
      pts <- polaris_isochrone_wavefront(graph, origin_id = s_id, max_cost = 300.0, metric = "time")
      hull <- concave_hull(pts)
      response_body <- polygon_to_geojson(hull, properties = list(origin = s_id, cutoff_seconds = 300))
    } else {
      status_code <- "404 Not Found"
      response_body <- "{\"error\":\"Endpoint not found\",\"valid_endpoints\":[\"/api/v1/health\",\"/api/v1/route\",\"/api/v1/isochrone\"]}"
    }

    # Send HTTP/1.1 response
    resp_header <- paste(
      sprintf("HTTP/1.1 %s\r", status_code),
      "Content-Type: application/json; charset=utf-8\r",
      "Access-Control-Allow-Origin: *\r",
      sprintf("Content-Length: %d\r", nchar(response_body, type = "bytes")),
      "Connection: close\r\n\r",
      sep = "\n"
    )

    writeChar(paste0(resp_header, response_body), conn, eos = NULL)
    close(conn)
  }

  cat(sprintf("[polaris-server] Server loop completed after %d requests.\n", request_count))
  invisible(request_count)
}
