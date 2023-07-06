# Polaris Unified Module Loader
# Loads all core, routing, matching, transit, isochrone, traffic, logistics, io, server, and render modules

polaris_load_all <- function(base_dir = NULL) {
  if (is.null(base_dir)) {
    # Detect location of current script
    cmd_args <- commandArgs(trailingOnly = FALSE)
    file_arg <- grep("--file=", cmd_args, value = TRUE)
    if (length(file_arg) > 0) {
      script_path <- sub("--file=", "", file_arg[1])
      base_dir <- normalizePath(file.path(dirname(script_path), ".."))
    } else {
      base_dir <- getwd()
    }
  }

  r_dir <- file.path(base_dir, "R")
  if (!dir.exists(r_dir)) {
    # If run from root
    r_dir <- "R"
  }

  source_order <- c(
    # 1. Core types and data structures
    file.path(r_dir, "core", "types.R"),
    file.path(r_dir, "core", "geodesy.R"),
    file.path(r_dir, "core", "priority_queue.R"),
    file.path(r_dir, "core", "spatial_index.R"),
    file.path(r_dir, "core", "spatial_kdtree.R"),
    file.path(r_dir, "core", "spatial_geohash.R"),
    file.path(r_dir, "core", "spatial_hex.R"),
    file.path(r_dir, "core", "graph_base.R"),
    file.path(r_dir, "core", "graph_builder.R"),

    # 2. Routing algorithms
    file.path(r_dir, "routing", "dijkstra.R"),
    file.path(r_dir, "routing", "bidirectional_dijkstra.R"),
    file.path(r_dir, "routing", "astar.R"),
    file.path(r_dir, "routing", "alt.R"),
    file.path(r_dir, "routing", "contraction_hierarchies.R"),
    file.path(r_dir, "routing", "turn_restrictions.R"),
    file.path(r_dir, "routing", "matrix.R"),
    file.path(r_dir, "routing", "multi_modal.R"),

    # 3. Map matching
    file.path(r_dir, "matching", "emission_model.R"),
    file.path(r_dir, "matching", "transition_model.R"),
    file.path(r_dir, "matching", "kalman_filter.R"),
    file.path(r_dir, "matching", "candidate_search.R"),
    file.path(r_dir, "matching", "viterbi.R"),
    file.path(r_dir, "matching", "map_matcher.R"),

    # 4. Public transit
    file.path(r_dir, "transit", "gtfs_parser.R"),
    file.path(r_dir, "transit", "transit_graph.R"),
    file.path(r_dir, "transit", "raptor.R"),
    file.path(r_dir, "transit", "raptor_range.R"),
    file.path(r_dir, "transit", "transfer_generator.R"),

    # 5. Isochrones
    file.path(r_dir, "isochrone", "isochrone_engine.R"),
    file.path(r_dir, "isochrone", "concave_hull.R"),
    file.path(r_dir, "isochrone", "marching_squares.R"),
    file.path(r_dir, "isochrone", "reachability_analysis.R"),

    # 6. Traffic assignment
    file.path(r_dir, "traffic", "bpr_function.R"),
    file.path(r_dir, "traffic", "all_or_nothing.R"),
    file.path(r_dir, "traffic", "frank_wolfe.R"),
    file.path(r_dir, "traffic", "dynamic_traffic.R"),

    # 7. Fleet logistics
    file.path(r_dir, "logistics", "vrp_model.R"),
    file.path(r_dir, "logistics", "clarke_wright.R"),
    file.path(r_dir, "logistics", "local_search.R"),
    file.path(r_dir, "logistics", "tabu_search.R"),
    file.path(r_dir, "logistics", "time_windows.R"),

    # 8. IO and serialization
    file.path(r_dir, "io", "geojson.R"),
    file.path(r_dir, "io", "osm_parser.R"),
    file.path(r_dir, "io", "serialization.R"),
    file.path(r_dir, "io", "csv_loader.R"),

    # 9. Server
    file.path(r_dir, "server", "http_server.R"),

    # 10. Visualization
    file.path(r_dir, "render", "terminal_render.R"),
    file.path(r_dir, "render", "svg_render.R")
  )

  for (f in source_order) {
    if (file.exists(f)) {
      source(f, local = FALSE)
    }
  }

  # Load native C acceleration if present
  accel_so <- file.path(base_dir, "src", "polaris_accel.so")
  if (file.exists(accel_so)) {
    tryCatch({
      dyn.load(accel_so)
    }, error = function(e) {
      # Fall back to pure R without error
    })
  }

  invisible(TRUE)
}
