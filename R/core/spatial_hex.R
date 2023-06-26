# Polaris Core Spatial Hex: Hexagonal Discrete Global Grid System
# Axial (q, r) and Cube (x, y, z) coordinates, k-ring expansion, and GIS polygon synthesis

SQRT_3 <- sqrt(3.0)

#' Convert Axial Coordinates (q, r) to Cube Coordinates (x, y, z)
#' Invariant: x + y + z = 0
#' @export
axial_to_cube <- function(q, r) {
  x <- as.numeric(q)
  z <- as.numeric(r)
  y <- -x - z
  c(x = x, y = y, z = z)
}

#' Convert Cube Coordinates (x, y, z) to Axial Coordinates (q, r)
#' @export
cube_to_axial <- function(x, y, z) {
  c(q = as.numeric(x), r = as.numeric(z))
}

#' Cube Coordinate Rounding
#' Rounds floating point cube coordinates to the nearest discrete integer hexagon
#' while strictly preserving x + y + z = 0.
#' @export
cube_round <- function(x, y, z) {
  rx <- round(x)
  ry <- round(y)
  rz <- round(z)

  x_diff <- abs(rx - x)
  y_diff <- abs(ry - y)
  z_diff <- abs(rz - z)

  if (x_diff > y_diff && x_diff > z_diff) {
    rx <- -ry - rz
  } else if (y_diff > z_diff) {
    ry <- -rx - rz
  } else {
    rz <- -rx - ry
  }

  c(x = as.integer(rx), y = as.integer(ry), z = as.integer(rz))
}

#' Hexagonal Grid Distance
#'
#' Computes the minimum number of hexagonal steps between two cells.
#'
#' @export
hex_distance <- function(q1, r1, q2, r2) {
  c1 <- axial_to_cube(q1, r1)
  c2 <- axial_to_cube(q2, r2)
  as.integer((abs(c1["x"] - c2["x"]) + abs(c1["y"] - c2["y"]) + abs(c1["z"] - c2["z"])) / 2.0)
}

#' Hexagonal Resolution Scale (in meters radius)
#' Resolution levels 0 to 12
#' @export
hex_resolution_radius <- function(resolution) {
  # Level 0: ~1,100 km, Level 7: ~1.2 km, Level 10: ~65 meters
  base_radius <- 1107412.0 # meters at resolution 0
  base_radius / (3.0^(resolution / 2.0))
}

#' Convert Geographic Coordinate to Hexagonal Cell ID at Target Resolution
#'
#' Projects WGS-84 coordinate (lat, lon) onto planar hexagonal grid patch.
#'
#' @param lat Latitude in degrees
#' @param lon Longitude in degrees
#' @param resolution Resolution level (0 to 12, default 7)
#' @return Hex cell string identifier 'res_q_r'
#' @export
geo_to_hex <- function(lat, lon, resolution = 7L) {
  res <- as.integer(max(0L, min(12L, resolution)))
  r_meters <- hex_resolution_radius(res)

  # Equirectangular planar projection centered on origin
  x_meters <- lon * DEG_TO_RAD * EARTH_RADIUS_MEAN * cos(deg2rad(lat))
  y_meters <- lat * DEG_TO_RAD * EARTH_RADIUS_MEAN

  # Flat-top hexagon fractional coordinates
  q_frac <- (2.0 / 3.0 * x_meters) / r_meters
  r_frac <- (-1.0 / 3.0 * x_meters + SQRT_3 / 3.0 * y_meters) / r_meters

  cube <- axial_to_cube(q_frac, r_frac)
  discrete_cube <- cube_round(cube["x"], cube["y"], cube["z"])
  axial <- cube_to_axial(discrete_cube["x"], discrete_cube["y"], discrete_cube["z"])

  sprintf("h_%d_%d_%d", res, as.integer(axial["q"]), as.integer(axial["r"]))
}

#' Convert Hex Cell ID to Geographic Center (lat, lon)
#'
#' @param hex_id Hex cell identifier 'h_res_q_r'
#' @return List with lat, lon, resolution, radius_meters
#' @export
hex_to_geo <- function(hex_id) {
  parts <- strsplit(hex_id, "_")[[1]]
  if (length(parts) != 4L || parts[1] != "h") {
    stop(sprintf("hex_to_geo: invalid hex identifier format '%s'", hex_id))
  }
  res <- as.integer(parts[2])
  q <- as.numeric(parts[3])
  r <- as.numeric(parts[4])

  r_meters <- hex_resolution_radius(res)

  # Inverse flat-top projection
  x_meters <- r_meters * (3.0 / 2.0 * q)
  y_meters <- r_meters * (SQRT_3 / 2.0 * q + SQRT_3 * r)

  lat <- (y_meters / EARTH_RADIUS_MEAN) * RAD_TO_DEG
  lat <- min(90.0, max(-90.0, lat))

  cos_lat <- cos(deg2rad(lat))
  lon <- if (abs(cos_lat) > 1e-6) {
    (x_meters / (EARTH_RADIUS_MEAN * cos_lat)) * RAD_TO_DEG
  } else {
    0.0
  }
  lon <- ((lon + 180.0) %% 360.0) - 180.0

  list(lat = lat, lon = lon, resolution = res, radius_meters = r_meters)
}

#' Hexagonal Cell Boundary Polygon
#'
#' Generates the 6 boundary vertices in geographic coordinates for GIS rendering.
#'
#' @param hex_id Hex cell string
#' @return Data frame with 7 rows (lat, lon) closing the polygon
#' @export
hex_boundary <- function(hex_id) {
  center <- hex_to_geo(hex_id)
  r_meters <- center$radius_meters
  cos_lat <- max(1e-6, cos(deg2rad(center$lat)))

  angles <- seq(0.0, 2.0 * pi, length.out = 7) # 6 vertices + 1 to close
  lats <- numeric(7)
  lons <- numeric(7)

  for (i in 1:7) {
    dx <- r_meters * cos(angles[i])
    dy <- r_meters * sin(angles[i])

    v_lat <- center$lat + (dy / EARTH_RADIUS_MEAN) * RAD_TO_DEG
    v_lon <- center$lon + (dx / (EARTH_RADIUS_MEAN * cos_lat)) * RAD_TO_DEG
    lats[i] <- min(90.0, max(-90.0, v_lat))
    lons[i] <- ((v_lon + 180.0) %% 360.0) - 180.0
  }

  data.frame(lat = lats, lon = lons)
}

#' K-Ring Neighborhood Expansion
#'
#' Returns all hexagon cell identifiers within distance k steps from the origin cell.
#'
#' @param hex_id Origin hex cell identifier
#' @param k Radius in steps (default 1)
#' @return Character vector of hex cell identifiers
#' @export
hex_kring <- function(hex_id, k = 1L) {
  parts <- strsplit(hex_id, "_")[[1]]
  res <- as.integer(parts[2])
  origin_q <- as.integer(parts[3])
  origin_r <- as.integer(parts[4])
  k <- as.integer(max(0L, k))

  if (k == 0L) return(hex_id)

  results <- character((3L * k * (k + 1L)) + 1L)
  idx <- 1L

  for (q in -k:k) {
    r1 <- max(-k, -q - k)
    r2 <- min(k, -q + k)
    for (r in r1:r2) {
      cur_q <- origin_q + q
      cur_r <- origin_r + r
      results[idx] <- sprintf("h_%d_%d_%d", res, cur_q, cur_r)
      idx <- idx + 1L
    }
  }

  results[seq_len(idx - 1L)]
}
