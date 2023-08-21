# Polaris Map Matching: Spatial Candidate Discovery & Projection
# R-tree branch search finding candidate road segments within search radius

#' Find Candidate Road Segments for a GPS Observation
#'
#' Queries the spatial road index to discover all nearby road segments within
#' the search radius, projecting the observation orthogonally onto each candidate.
#'
#' @param graph Base polaris_graph object
#' @param lat GPS observation latitude
#' @param lon GPS observation longitude
#' @param gps_bearing Optional GPS vehicle heading in degrees
#' @param max_radius_meters Spatial search radius in meters (default 50m)
#' @param max_candidates Maximum candidate segments to retain (default 10)
#' @return List of candidate state records
#' @export
find_candidate_segments <- function(graph, lat, lon,
                                    gps_bearing = NULL,
                                    max_radius_meters = 50.0,
                                    max_candidates = 10L) {
  # Query bounding box
  lat_delta <- (max_radius_meters / EARTH_RADIUS_MEAN) * RAD_TO_DEG
  cos_lat <- max(1e-6, cos(deg2rad(lat)))
  lon_delta <- (max_radius_meters / (EARTH_RADIUS_MEAN * cos_lat)) * RAD_TO_DEG

  q_box <- polaris_bbox(
    min_lat = lat - lat_delta,
    min_lon = lon - lon_delta,
    max_lat = lat + lat_delta,
    max_lon = lon + lon_delta
  )

  candidates <- list()

  for (e_id in graph$edge_ids) {
    edge_obj <- graph$get_edge(e_id)
    s_coord <- graph$node_coords[[edge_obj$source]]
    t_coord <- graph$node_coords[[edge_obj$target]]

    # Quick bounding box rejection
    e_min_lat <- min(s_coord$lat, t_coord$lat)
    e_max_lat <- max(s_coord$lat, t_coord$lat)
    e_min_lon <- min(s_coord$lon, t_coord$lon)
    e_max_lon <- max(s_coord$lon, t_coord$lon)

    if (e_max_lat < q_box$min_lat || e_min_lat > q_box$max_lat ||
        e_max_lon < q_box$min_lon || e_min_lon > q_box$max_lon) {
      next
    }

    # Project point onto segment
    proj <- project_point_to_segment(
      lat = lat, lon = lon,
      lat_start = s_coord$lat, lon_start = s_coord$lon,
      lat_end = t_coord$lat, lon_end = t_coord$lon
    )

    if (proj$distance_meters <= max_radius_meters) {
      # Compute road bearing
      rd_bearing <- initial_bearing(s_coord$lat, s_coord$lon, t_coord$lat, t_coord$lon)
      h_diff <- NA_real_
      if (!is.null(gps_bearing) && !is.na(gps_bearing)) {
        h_diff <- abs(((gps_bearing - rd_bearing + 180.0) %% 360.0) - 180.0)
      }

      candidates[[length(candidates) + 1L]] <- list(
        edge_id = e_id,
        source = edge_obj$source,
        target = edge_obj$target,
        proj_lat = proj$proj_lat,
        proj_lon = proj$proj_lon,
        distance_meters = proj$distance_meters,
        fraction = proj$fraction,
        road_bearing = rd_bearing,
        heading_diff = h_diff,
        oneway = edge_obj$oneway
      )
    }
  }

  if (length(candidates) == 0L) {
    return(list())
  }

  # Sort by projection distance ascending
  ord <- order(vapply(candidates, function(c) c$distance_meters, numeric(1)))
  sorted_cand <- candidates[ord]

  if (length(sorted_cand) > max_candidates) {
    sorted_cand <- sorted_cand[seq_len(max_candidates)]
  }

  sorted_cand
}
