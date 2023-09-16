# Polaris Isochrone: Demographic Catchment & Point-in-Polygon Reachability
# Ray-casting point-in-polygon tests and urban accessibility scoring

#' Ray-Casting 2D Point-in-Polygon Test
#'
#' Tests whether a query point (lat, lon) lies inside a closed polygon boundary.
#'
#' @param lat Query latitude
#' @param lon Query longitude
#' @param poly_lats Numeric vector of polygon latitudes
#' @param poly_lons Numeric vector of polygon longitudes
#' @return Logical TRUE if point is inside polygon
#' @export
point_in_polygon <- function(lat, lon, poly_lats, poly_lons) {
  n <- length(poly_lats)
  if (n < 3L) return(FALSE)

  inside <- FALSE
  j <- n

  for (i in seq_len(n)) {
    yi <- poly_lats[i]
    xi <- poly_lons[i]
    yj <- poly_lats[j]
    xj <- poly_lons[j]

    # Ray casting along horizontal axis
    intersect_edge <- ((yi > lat) != (yj > lat)) &&
      (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi)

    if (intersect_edge) {
      inside <- !inside
    }
    j <- i
  }

  inside
}

#' Catchment Facility Accessibility Scoring
#'
#' Evaluates which target facilities (e.g. clinics, schools, customers)
#' fall within the reachable isochrone boundary polygon.
#'
#' @param isochrone_poly Data frame with lat, lon columns of boundary polygon
#' @param facilities_df Data frame of facilities with id, lat, lon, and optional weight
#' @return Data frame of covered facilities with is_covered flag and summary
#' @export
evaluate_isochrone_catchment <- function(isochrone_poly, facilities_df) {
  n_fac <- nrow(facilities_df)
  is_cov <- logical(n_fac)
  poly_lats <- isochrone_poly$lat
  poly_lons <- isochrone_poly$lon

  for (i in seq_len(n_fac)) {
    is_cov[i] <- point_in_polygon(
      lat = facilities_df$lat[i],
      lon = facilities_df$lon[i],
      poly_lats = poly_lats,
      poly_lons = poly_lons
    )
  }

  has_weight <- "weight" %in% names(facilities_df)
  weights <- if (has_weight) as.numeric(facilities_df$weight) else rep(1.0, n_fac)

  total_covered_weight <- sum(weights[is_cov])
  total_weight <- sum(weights)

  list(
    facilities = cbind(facilities_df, is_covered = is_cov),
    covered_count = sum(is_cov),
    total_count = n_fac,
    coverage_ratio = if (n_fac > 0) sum(is_cov) / n_fac else 0.0,
    weighted_coverage_ratio = if (total_weight > 0) total_covered_weight / total_weight else 0.0
  )
}
