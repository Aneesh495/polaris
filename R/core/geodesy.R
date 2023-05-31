# Polaris Core Geodesy: WGS-84 Ellipsoidal Computations & Spherical Trigonometry
# High-precision ellipsoidal geodesics, Vincenty equations, Haversine, and cross-track projections

# WGS-84 Reference Ellipsoid Parameters
WGS84_A <- 6378137.0             # Semi-major axis (meters)
WGS84_F <- 1.0 / 298.257223563   # Flattening
WGS84_B <- WGS84_A * (1.0 - WGS84_F) # Semi-minor axis (meters)
EARTH_RADIUS_MEAN <- 6371008.8   # Mean earth radius in meters

DEG_TO_RAD <- pi / 180.0
RAD_TO_DEG <- 180.0 / pi

#' Convert Degrees to Radians
#' @export
deg2rad <- function(deg) {
  deg * DEG_TO_RAD
}

#' Convert Radians to Degrees
#' @export
rad2deg <- function(rad) {
  rad * RAD_TO_DEG
}

#' Haversine Great Circle Distance
#'
#' Fast spherical geodesic distance between two points in meters.
#'
#' @param lat1 Latitude of point 1 in degrees
#' @param lon1 Longitude of point 1 in degrees
#' @param lat2 Latitude of point 2 in degrees
#' @param lon2 Longitude of point 2 in degrees
#' @param radius Sphere radius in meters (default mean Earth radius)
#' @return Distance in meters
#' @export
haversine_distance <- function(lat1, lon1, lat2, lon2, radius = EARTH_RADIUS_MEAN) {
  phi1 <- lat1 * DEG_TO_RAD
  phi2 <- lat2 * DEG_TO_RAD
  delta_phi <- (lat2 - lat1) * DEG_TO_RAD
  delta_lambda <- (lon2 - lon1) * DEG_TO_RAD

  sin_half_dphi <- sin(delta_phi / 2.0)
  sin_half_dlam <- sin(delta_lambda / 2.0)

  a <- sin_half_dphi * sin_half_dphi +
       cos(phi1) * cos(phi2) * sin_half_dlam * sin_half_dlam

  # Guard against numerical floating point roundoff exceeding 1.0
  a <- min(1.0, max(0.0, a))
  c <- 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
  radius * c
}

#' Vincenty Inverse Solution on WGS-84 Ellipsoid
#'
#' Calculates the exact geodesic distance, forward azimuth, and reverse azimuth
#' between two points on the WGS-84 reference ellipsoid with millimeter precision.
#'
#' @param lat1 Origin latitude in degrees
#' @param lon1 Origin longitude in degrees
#' @param lat2 Destination latitude in degrees
#' @param lon2 Destination longitude in degrees
#' @param max_iter Maximum iterations for convergence loop
#' @param tol Convergence tolerance in radians
#' @return List with distance (meters), initial_bearing (deg), final_bearing (deg)
#' @export
vincenty_inverse <- function(lat1, lon1, lat2, lon2, max_iter = 200, tol = 1e-12) {
  if (abs(lat1 - lat2) < 1e-9 && abs(lon1 - lon2) < 1e-9) {
    return(list(distance = 0.0, initial_bearing = 0.0, final_bearing = 0.0, converged = TRUE))
  }

  phi1 <- lat1 * DEG_TO_RAD
  phi2 <- lat2 * DEG_TO_RAD
  L <- (lon2 - lon1) * DEG_TO_RAD

  U1 <- atan((1.0 - WGS84_F) * tan(phi1))
  U2 <- atan((1.0 - WGS84_F) * tan(phi2))

  sinU1 <- sin(U1)
  cosU1 <- cos(U1)
  sinU2 <- sin(U2)
  cosU2 <- cos(U2)

  lambda <- L
  iter <- 0
  converged <- FALSE

  while (iter < max_iter) {
    iter <- iter + 1
    sin_lambda <- sin(lambda)
    cos_lambda <- cos(lambda)

    sin_sigma <- sqrt((cosU2 * sin_lambda)^2 +
                      (cosU1 * sinU2 - sinU1 * cosU2 * cos_lambda)^2)

    if (sin_sigma < 1e-15) {
      # Coincident or antipodal points
      return(list(distance = 0.0, initial_bearing = 0.0, final_bearing = 0.0, converged = TRUE))
    }

    cos_sigma <- sinU1 * sinU2 + cosU1 * cosU2 * cos_lambda
    sigma <- atan2(sin_sigma, cos_sigma)

    sin_alpha <- (cosU1 * cosU2 * sin_lambda) / sin_sigma
    cos2_alpha <- 1.0 - sin_alpha * sin_alpha

    if (cos2_alpha == 0.0) {
      cos2_sigma_m <- 0.0 # Equatorial line
    } else {
      cos2_sigma_m <- cos_sigma - (2.0 * sinU1 * sinU2) / cos2_alpha
    }

    C <- (WGS84_F / 16.0) * cos2_alpha * (4.0 + WGS84_F * (4.0 - 3.0 * cos2_alpha))
    lambda_prev <- lambda
    lambda <- L + (1.0 - C) * WGS84_F * sin_alpha *
      (sigma + C * sin_sigma * (cos2_sigma_m + C * cos_sigma * (-1.0 + 2.0 * cos2_sigma_m^2)))

    if (abs(lambda - lambda_prev) < tol) {
      converged <- TRUE
      break
    }
  }

  if (!converged) {
    # Fall back cleanly to Haversine if antipodal convergence fails
    dist_fallback <- haversine_distance(lat1, lon1, lat2, lon2)
    b_init <- initial_bearing(lat1, lon1, lat2, lon2)
    return(list(distance = dist_fallback, initial_bearing = b_init, final_bearing = b_init, converged = FALSE))
  }

  u2 <- cos2_alpha * ((WGS84_A^2 - WGS84_B^2) / (WGS84_B^2))
  A <- 1.0 + (u2 / 16384.0) * (4096.0 + u2 * (-768.0 + u2 * (320.0 - 175.0 * u2)))
  B <- (u2 / 1024.0) * (256.0 + u2 * (-128.0 + u2 * (74.0 - 47.0 * u2)))

  delta_sigma <- B * sin_sigma * (cos2_sigma_m + (B / 4.0) *
    (cos_sigma * (-1.0 + 2.0 * cos2_sigma_m^2) -
     (B / 6.0) * cos2_sigma_m * (-3.0 + 4.0 * sin_sigma^2) * (-3.0 + 4.0 * cos2_sigma_m^2)))

  s <- WGS84_B * A * (sigma - delta_sigma)

  # Initial and final bearings
  alpha1 <- atan2(cosU2 * sin(lambda), cosU1 * sinU2 - sinU1 * cosU2 * cos(lambda))
  alpha2 <- atan2(cosU1 * sin(lambda), -sinU1 * cosU2 + cosU1 * sinU2 * cos(lambda))

  init_bearing_deg <- (alpha1 * RAD_TO_DEG + 360.0) %% 360.0
  final_bearing_deg <- (alpha2 * RAD_TO_DEG + 360.0) %% 360.0

  list(
    distance = s,
    initial_bearing = init_bearing_deg,
    final_bearing = final_bearing_deg,
    converged = TRUE
  )
}

#' Great Circle Initial Bearing
#'
#' Computes the forward compass heading from point 1 to point 2 in degrees [0, 360).
#'
#' @export
initial_bearing <- function(lat1, lon1, lat2, lon2) {
  phi1 <- lat1 * DEG_TO_RAD
  phi2 <- lat2 * DEG_TO_RAD
  delta_lambda <- (lon2 - lon1) * DEG_TO_RAD

  y <- sin(delta_lambda) * cos(phi2)
  x <- cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(delta_lambda)

  theta <- atan2(y, x)
  (theta * RAD_TO_DEG + 360.0) %% 360.0
}

#' Cross-Track Distance
#'
#' Perpendicular distance in meters from a test point to the great-circle arc
#' passing through start and end points. Negative indicates left, positive right.
#'
#' @param lat Test latitude
#' @param lon Test longitude
#' @param lat_start Arc start latitude
#' @param lon_start Arc start longitude
#' @param lat_end Arc end latitude
#' @param lon_end Arc end longitude
#' @param radius Sphere radius
#' @return Cross-track distance in meters
#' @export
cross_track_distance <- function(lat, lon, lat_start, lon_start, lat_end, lon_end,
                                 radius = EARTH_RADIUS_MEAN) {
  d13 <- haversine_distance(lat_start, lon_start, lat, lon, radius = radius) / radius
  theta13 <- initial_bearing(lat_start, lon_start, lat, lon) * DEG_TO_RAD
  theta12 <- initial_bearing(lat_start, lon_start, lat_end, lon_end) * DEG_TO_RAD

  asin_val <- sin(d13) * sin(theta13 - theta12)
  asin_val <- min(1.0, max(-1.0, asin_val))
  asin(asin_val) * radius
}

#' Along-Track Distance
#'
#' Distance along the great-circle arc from start to the orthogonal projection of test point.
#'
#' @export
along_track_distance <- function(lat, lon, lat_start, lon_start, lat_end, lon_end,
                                radius = EARTH_RADIUS_MEAN) {
  d13 <- haversine_distance(lat_start, lon_start, lat, lon, radius = radius) / radius
  dxt <- cross_track_distance(lat, lon, lat_start, lon_start, lat_end, lon_end, radius = radius) / radius

  cos_d13 <- cos(d13)
  cos_dxt <- cos(dxt)
  val <- cos_d13 / cos_dxt
  val <- min(1.0, max(-1.0, val))
  acos(val) * radius
}

#' Project Point onto Geographic Road Segment
#'
#' Finds the closest point on segment (lat_start, lon_start) -> (lat_end, lon_end)
#' to a target point (lat, lon). Clamps to endpoints if projection falls outside segment.
#'
#' @return List with proj_lat, proj_lon, distance_meters, fraction_along (0 to 1)
#' @export
project_point_to_segment <- function(lat, lon, lat_start, lon_start, lat_end, lon_end) {
  seg_length <- haversine_distance(lat_start, lon_start, lat_end, lon_end)
  if (seg_length < 1e-4) {
    # Degenerate zero-length segment
    d <- haversine_distance(lat, lon, lat_start, lon_start)
    return(list(proj_lat = lat_start, proj_lon = lon_start, distance_meters = d, fraction = 0.0))
  }

  atd <- along_track_distance(lat, lon, lat_start, lon_start, lat_end, lon_end)

  if (atd <= 0.0) {
    d <- haversine_distance(lat, lon, lat_start, lon_start)
    return(list(proj_lat = lat_start, proj_lon = lon_start, distance_meters = d, fraction = 0.0))
  } else if (atd >= seg_length) {
    d <- haversine_distance(lat, lon, lat_end, lon_end)
    return(list(proj_lat = lat_end, proj_lon = lon_end, distance_meters = d, fraction = 1.0))
  } else {
    fraction <- atd / seg_length
    # Linear interpolation on local spherical patch
    proj_lat <- lat_start + fraction * (lat_end - lat_start)
    proj_lon <- lon_start + fraction * (lon_end - lon_start)
    d <- haversine_distance(lat, lon, proj_lat, proj_lon)
    return(list(proj_lat = proj_lat, proj_lon = proj_lon, distance_meters = d, fraction = fraction))
  }
}

#' Polyline Total Length
#'
#' Computes the cumulative distance along an ordered sequence of coordinates in meters.
#'
#' @param coords List of polaris_coordinate objects or data frame with lat/lon
#' @export
polyline_length <- function(coords) {
  if (is.data.frame(coords)) {
    n <- nrow(coords)
    if (n < 2) return(0.0)
    total <- 0.0
    for (i in seq_len(n - 1)) {
      total <- total + haversine_distance(coords$lat[i], coords$lon[i],
                                          coords$lat[i + 1], coords$lon[i + 1])
    }
    return(total)
  }
  n <- length(coords)
  if (n < 2) return(0.0)
  total <- 0.0
  for (i in seq_len(n - 1)) {
    total <- total + haversine_distance(coords[[i]]$lat, coords[[i]]$lon,
                                        coords[[i + 1]]$lat, coords[[i + 1]]$lon)
  }
  total
}
