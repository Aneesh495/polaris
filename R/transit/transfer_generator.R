# Polaris Public Transit: Footpath Transfer Generator
# Synthesizes pedestrian transfers between transit stops and street graph vertices

#' Link Transit Stops to Street Network Graph Vertices
#'
#' Finds the nearest road vertex for every transit stop in a GTFS feed
#' and creates virtual walk transfer edges.
#'
#' @param raptor_net polaris_raptor_network object
#' @param street_graph Base polaris_graph road network
#' @param max_snap_radius_meters Max distance to snap stop to street network (default 250m)
#' @return Named list of stop_id -> list(street_node_id, snap_distance_m, walk_time_sec)
#' @export
link_transit_stops_to_streets <- function(raptor_net, street_graph,
                                          max_snap_radius_meters = 250.0) {
  street_kd <- build_graph_kdtree(street_graph)
  links <- list()

  for (s_id in raptor_net$stop_ids) {
    coord <- raptor_net$stop_coords[[s_id]]
    nearest <- street_kd$nearest(coord$lat, coord$lon)

    if (!is.null(nearest) && nearest$distance_meters <= max_snap_radius_meters) {
      walk_sec <- as.integer(ceiling(nearest$distance_meters / 1.2)) # 1.2 m/s walk speed
      links[[s_id]] <- list(
        stop_id = s_id,
        street_node_id = nearest$id,
        snap_distance_m = nearest$distance_meters,
        walk_time_sec = walk_sec
      )
    }
  }

  links
}
