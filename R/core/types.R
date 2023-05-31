# Polaris Spatial Foundation: Data Types and Invariant Models
# High-performance spatial-temporal graph structures

#' Spatial Coordinate in WGS-84 Datum
#'
#' Represents a geographic coordinate on the WGS-84 reference ellipsoid,
#' optionally with orthometric elevation in meters.
#'
#' @param lat Latitude in decimal degrees [-90.0, 90.0]
#' @param lon Longitude in decimal degrees [-180.0, 180.0]
#' @param ele Optional elevation in meters above sea level
#' @return An S3 object of class polaris_coordinate
#' @export
polaris_coordinate <- function(lat, lon, ele = 0.0) {
  if (!is.numeric(lat) || length(lat) != 1 || is.na(lat) || lat < -90.0 || lat > 90.0) {
    stop("polaris_coordinate: lat must be a finite numeric scalar in [-90.0, 90.0]")
  }
  if (!is.numeric(lon) || length(lon) != 1 || is.na(lon) || lon < -180.0 || lon > 180.0) {
    stop("polaris_coordinate: lon must be a finite numeric scalar in [-180.0, 180.0]")
  }
  if (!is.numeric(ele) || length(ele) != 1 || is.na(ele)) {
    ele <- 0.0
  }
  structure(
    list(lat = as.numeric(lat), lon = as.numeric(lon), ele = as.numeric(ele)),
    class = "polaris_coordinate"
  )
}

#' Print method for polaris_coordinate
#' @export
print.polaris_coordinate <- function(x, ...) {
  cat(sprintf("<polaris_coordinate lat=%.6f lon=%.6f ele=%.1fm>\n", x$lat, x$lon, x$ele))
  invisible(x)
}

#' Spatial Bounding Box
#'
#' Minimum bounding rectangle in geographic coordinates.
#'
#' @param min_lat Minimum latitude
#' @param min_lon Minimum longitude
#' @param max_lat Maximum latitude
#' @param max_lon Maximum longitude
#' @return An S3 object of class polaris_bbox
#' @export
polaris_bbox <- function(min_lat, min_lon, max_lat, max_lon) {
  if (min_lat > max_lat) {
    stop("polaris_bbox: min_lat cannot exceed max_lat")
  }
  if (min_lon > max_lon) {
    stop("polaris_bbox: min_lon cannot exceed max_lon")
  }
  structure(
    list(
      min_lat = as.numeric(min_lat),
      min_lon = as.numeric(min_lon),
      max_lat = as.numeric(max_lat),
      max_lon = as.numeric(max_lon)
    ),
    class = "polaris_bbox"
  )
}

#' Check if a point lies inside a bounding box
#' @export
bbox_contains <- function(bbox, coord) {
  coord$lat >= bbox$min_lat && coord$lat <= bbox$max_lat &&
    coord$lon >= bbox$min_lon && coord$lon <= bbox$max_lon
}

#' Expand bounding box to include a coordinate
#' @export
bbox_expand <- function(bbox, coord) {
  polaris_bbox(
    min_lat = min(bbox$min_lat, coord$lat),
    min_lon = min(bbox$min_lon, coord$lon),
    max_lat = max(bbox$max_lat, coord$lat),
    max_lon = max(bbox$max_lon, coord$lon)
  )
}

#' Graph Node Definition
#'
#' Represents a discrete intersection or vertex in a routing network.
#'
#' @param id Unique integer or character vertex identifier
#' @param lat Latitude in decimal degrees
#' @param lon Longitude in decimal degrees
#' @param ele Elevation in meters
#' @param tags Named list or vector of arbitrary metadata attributes
#' @return An S3 object of class polaris_node
#' @export
polaris_node <- function(id, lat, lon, ele = 0.0, tags = list()) {
  coord <- polaris_coordinate(lat, lon, ele)
  structure(
    list(
      id = as.character(id),
      coord = coord,
      tags = as.list(tags)
    ),
    class = "polaris_node"
  )
}

#' Graph Directed Edge Definition
#'
#' Represents a directional traversable link between two vertices.
#'
#' @param id Unique edge identifier
#' @param source Source node identifier
#' @param target Target node identifier
#' @param distance Geometric length in meters
#' @param travel_time Free-flow travel time in seconds
#' @param speed_limit Speed limit in km/h
#' @param oneway Boolean indicating directional constraint
#' @param highway_type Road classification string
#' @param geometry Optional list of coordinates along the edge polyline
#' @return An S3 object of class polaris_edge
#' @export
polaris_edge <- function(id, source, target, distance, travel_time = NULL,
                         speed_limit = 50.0, oneway = FALSE,
                         highway_type = "primary", geometry = list()) {
  if (distance < 0.0) {
    stop("polaris_edge: distance must be non-negative")
  }
  if (is.null(travel_time)) {
    # Speed in meters per second: speed_limit * (1000 / 3600)
    speed_ms <- max(1.0, speed_limit * (1000.0 / 3600.0))
    travel_time <- distance / speed_ms
  }
  structure(
    list(
      id = as.character(id),
      source = as.character(source),
      target = as.character(target),
      distance = as.numeric(distance),
      travel_time = as.numeric(travel_time),
      speed_limit = as.numeric(speed_limit),
      oneway = as.logical(oneway),
      highway_type = as.character(highway_type),
      geometry = geometry
    ),
    class = "polaris_edge"
  )
}

#' Turn Restriction Definition
#'
#' Defines prohibited or penalized maneuvers across adjacent edges.
#'
#' @param from_edge Identifier of incoming edge
#' @param via_node Identifier of intermediate intersection vertex
#' @param to_edge Identifier of outgoing edge
#' @param restriction_type One of 'no_left_turn', 'no_right_turn', 'no_u_turn', 'only_straight_on', 'penalty'
#' @param penalty_seconds Additional delay in seconds if restriction_type == 'penalty'
#' @export
polaris_turn_restriction <- function(from_edge, via_node, to_edge,
                                    restriction_type = "no_u_turn",
                                    penalty_seconds = 0.0) {
  structure(
    list(
      from_edge = as.character(from_edge),
      via_node = as.character(via_node),
      to_edge = as.character(to_edge),
      restriction_type = as.character(restriction_type),
      penalty_seconds = as.numeric(penalty_seconds)
    ),
    class = "polaris_turn_restriction"
  )
}

#' Path Route Result
#'
#' Encapsulates computed path trajectory, summary statistics, and traversal steps.
#'
#' @export
polaris_route_result <- function(nodes, edges, total_distance, total_time,
                                geometry = list(), algorithm = "dijkstra",
                                status = "OK") {
  structure(
    list(
      nodes = as.character(nodes),
      edges = as.character(edges),
      total_distance = as.numeric(total_distance),
      total_time = as.numeric(total_time),
      geometry = geometry,
      algorithm = as.character(algorithm),
      status = as.character(status)
    ),
    class = "polaris_route_result"
  )
}

#' Print method for polaris_route_result
#' @export
print.polaris_route_result <- function(x, ...) {
  cat(sprintf("<polaris_route_result status=%s algo=%s dist=%.2fm time=%.2fs steps=%d>\n",
              x$status, x$algorithm, x$total_distance, x$total_time, length(x$nodes)))
  invisible(x)
}
