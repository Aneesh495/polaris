# Polaris IO: Zero-Dependency GeoJSON FeatureCollection Serializer
# Converts routes, isochrones, GPS tracks, and network topologies to RFC 7946 GeoJSON

#' Convert Polaris Route Result to GeoJSON Feature
#'
#' Serializes route geometry into a standard GeoJSON LineString Feature with traversal metadata.
#'
#' @param route_result polaris_route_result object
#' @param properties Optional list of additional metadata attributes
#' @return JSON string formatted as GeoJSON
#' @export
route_to_geojson <- function(route_result, properties = list()) {
  coords <- route_result$geometry
  n <- length(coords)

  coord_pairs <- character(n)
  for (i in seq_len(n)) {
    c_pt <- coords[[i]]
    coord_pairs[i] <- sprintf("[%.6f,%.6f]", c_pt$lon, c_pt$lat)
  }
  coords_json <- paste0("[", paste(coord_pairs, collapse = ","), "]")

  props <- c(list(
    algorithm = route_result$algorithm,
    distance_meters = round(route_result$total_distance, 2),
    travel_time_seconds = round(route_result$total_time, 2),
    step_count = length(route_result$nodes)
  ), properties)

  prop_parts <- character(length(props))
  for (k in seq_along(props)) {
    val <- props[[k]]
    val_str <- if (is.numeric(val)) as.character(val) else sprintf("\"%s\"", as.character(val))
    prop_parts[k] <- sprintf("\"%s\":%s", names(props)[k], val_str)
  }
  props_json <- paste0("{", paste(prop_parts, collapse = ","), "}")

  sprintf(
    "{\"type\":\"Feature\",\"geometry\":{\"type\":\"LineString\",\"coordinates\":%s},\"properties\":%s}",
    coords_json, props_json
  )
}

#' Convert Boundary Polygon to GeoJSON Polygon Feature
#'
#' Serializes closed boundary polygons (e.g. isochrones, hex cells) to GeoJSON.
#'
#' @param polygon_df Data frame with lat and lon columns (first and last coordinate identical)
#' @param properties Named list of metadata attributes
#' @return GeoJSON Feature string
#' @export
polygon_to_geojson <- function(polygon_df, properties = list()) {
  n <- nrow(polygon_df)
  coord_pairs <- character(n)
  for (i in seq_len(n)) {
    coord_pairs[i] <- sprintf("[%.6f,%.6f]", polygon_df$lon[i], polygon_df$lat[i])
  }
  ring_json <- paste0("[", paste(coord_pairs, collapse = ","), "]")

  props_parts <- character(length(properties))
  for (k in seq_along(properties)) {
    val <- properties[[k]]
    val_str <- if (is.numeric(val)) as.character(val) else sprintf("\"%s\"", as.character(val))
    props_parts[k] <- sprintf("\"%s\":%s", names(properties)[k], val_str)
  }
  props_json <- paste0("{", paste(props_parts, collapse = ","), "}")

  sprintf(
    "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[%s]},\"properties\":%s}",
    ring_json, props_json
  )
}

#' Wrap Multiple GeoJSON Features into a FeatureCollection
#'
#' @param features Character vector of GeoJSON Feature strings
#' @return Complete RFC 7946 FeatureCollection string
#' @export
to_feature_collection <- function(features) {
  sprintf(
    "{\"type\":\"FeatureCollection\",\"features\":[%s]}",
    paste(features, collapse = ",")
  )
}
