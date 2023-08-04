# Polaris Routing Engine: Multi-Modal Network Routing
# Integrates vehicular, pedestrian, and bicycle network topologies with mode transfer edges

#' Check if Road Segment Supports Target Travel Mode
#'
#' @param highway_type OpenStreetMap highway tag string
#' @param mode Travel mode: 'drive', 'bicycle', or 'walk'
#' @return Logical indicating traversability
#' @export
is_mode_permitted <- function(highway_type, mode = "drive") {
  hwy <- tolower(trimws(highway_type))

  if (mode == "drive") {
    # Motor vehicles permitted on standard roads, prohibited on footways/steps/cycleways
    forbidden <- c("footway", "pedestrian", "path", "steps", "cycleway", "bridleway")
    return(!(hwy %in% forbidden))
  } else if (mode == "bicycle") {
    # Bicycles permitted on cycleways and general roads, prohibited on motorways
    forbidden <- c("motorway", "motorway_link", "steps")
    return(!(hwy %in% forbidden))
  } else if (mode == "walk") {
    # Pedestrians permitted on footways, paths, urban streets, prohibited on motorways/trunks
    forbidden <- c("motorway", "motorway_link", "trunk", "trunk_link")
    return(!(hwy %in% forbidden))
  }
  TRUE
}

#' Extract Single-Mode Subgraph
#'
#' Creates a filtered graph instance tailored to the speed profile and access
#' constraints of the specified transportation mode.
#'
#' @param graph Base polaris_graph
#' @param mode 'drive', 'bicycle', or 'walk'
#' @return A new polaris_graph instance
#' @export
extract_mode_subgraph <- function(graph, mode = "drive") {
  sub_g <- polaris_graph()

  # Speed profiles by mode (km/h)
  walk_speed <- 4.8
  bike_speed <- 15.0

  for (e_id in graph$edge_ids) {
    e <- graph$get_edge(e_id)
    if (is_mode_permitted(e$highway_type, mode = mode)) {
      # Ensure vertices exist in sub_g
      s_nd <- graph$get_node(e$source)
      t_nd <- graph$get_node(e$target)
      sub_g$add_node(s_nd$id, s_nd$coord$lat, s_nd$coord$lon, s_nd$coord$ele, s_nd$tags)
      sub_g$add_node(t_nd$id, t_nd$coord$lat, t_nd$coord$lon, t_nd$coord$ele, t_nd$tags)

      # Adjust speed limits and travel times for mode
      spd <- if (mode == "walk") {
        walk_speed
      } else if (mode == "bicycle") {
        min(bike_speed, e$speed_limit)
      } else {
        e$speed_limit
      }

      time_sec <- e$distance / (spd * 1000.0 / 3600.0)

      sub_g$add_edge(
        id = e$id,
        source = e$source,
        target = e$target,
        distance = e$distance,
        travel_time = time_sec,
        speed_limit = spd,
        oneway = (mode == "drive" && e$oneway), # Pedestrians walk both ways
        highway_type = e$highway_type,
        geometry = e$geometry
      )
    }
  }

  sub_g$build_csr()
  sub_g
}

#' Build Unified Multi-Modal Graph with Transfer Hubs
#'
#' Combines vehicular, cycling, and pedestrian networks into an integrated
#' layer, inserting mode transfer edges at interchange vertices (e.g. parking).
#'
#' @param graph Base polaris_graph
#' @param transfer_nodes Character vector of node IDs where mode switching is allowed
#' @param transfer_penalty_sec Delay penalty in seconds for mode transitions (default 120s)
#' @return Multi-modal polaris_graph with namespaced mode vertices: 'mode:node_id'
#' @export
build_multi_modal_graph <- function(graph, transfer_nodes = character(0),
                                    transfer_penalty_sec = 120.0) {
  mm_g <- polaris_graph()
  modes <- c("drive", "bicycle", "walk")

  # Add mode-specific vertices: e.g. 'walk:node_1', 'drive:node_1'
  for (m in modes) {
    for (nd_id in graph$node_ids) {
      nd <- graph$get_node(nd_id)
      mm_g$add_node(
        id = paste0(m, ":", nd_id),
        lat = nd$coord$lat,
        lon = nd$coord$lon,
        ele = nd$coord$ele,
        tags = c(nd$tags, list(mode = m, base_id = nd_id))
      )
    }
  }

  # Add mode-specific edges
  for (m in modes) {
    for (e_id in graph$edge_ids) {
      e <- graph$get_edge(e_id)
      if (is_mode_permitted(e$highway_type, mode = m)) {
        spd <- if (m == "walk") 4.8 else if (m == "bicycle") min(15.0, e$speed_limit) else e$speed_limit
        time_sec <- e$distance / (spd * 1000.0 / 3600.0)

        mm_g$add_edge(
          id = paste0(m, ":", e$id),
          source = paste0(m, ":", e$source),
          target = paste0(m, ":", e$target),
          distance = e$distance,
          travel_time = time_sec,
          speed_limit = spd,
          oneway = (m == "drive" && e$oneway),
          highway_type = e$highway_type
        )
      }
    }
  }

  # Add inter-modal transfer links at designated hubs
  for (hub_id in transfer_nodes) {
    # Connect drive <-> walk, bicycle <-> walk
    transitions <- list(
      c("drive", "walk"), c("walk", "drive"),
      c("bicycle", "walk"), c("walk", "bicycle")
    )
    for (t in transitions) {
      from_node <- paste0(t[1], ":", hub_id)
      to_node   <- paste0(t[2], ":", hub_id)
      mm_g$add_edge(
        id = sprintf("xfer_%s_%s_%s", hub_id, t[1], t[2]),
        source = from_node,
        target = to_node,
        distance = 0.0,
        travel_time = transfer_penalty_sec,
        speed_limit = 1.0,
        oneway = TRUE,
        highway_type = "transfer"
      )
    }
  }

  mm_g$build_csr()
  mm_g
}
