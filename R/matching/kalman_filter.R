# Polaris Map Matching: Spatial Extended Kalman Filter (EKF)
# Kinematic state smoothing, velocity estimation, and GPS innovation outlier rejection

#' Spatial Kalman Filter for GPS Telemetry
#'
#' Filters high-frequency GPS jitter and estimates continuous vehicle velocity
#' and heading vectors using a planar kinematic constant-velocity state-space model.
#'
#' @param lats Numeric vector of raw GPS latitudes
#' @param lons Numeric vector of raw GPS longitudes
#' @param timestamps Numeric vector of POSIXct or epoch seconds
#' @param gps_noise_sigma Measurement error standard deviation in meters (default 4.0m)
#' @param accel_noise_sigma Driver acceleration process noise in m/s^2 (default 1.5 m/s^2)
#' @param outlier_threshold_nis Chi-squared outlier rejection threshold on NIS (default 9.21)
#' @return Data frame with smoothed lat, lon, speed_mps, heading_deg, is_outlier
#' @export
polaris_kalman_filter <- function(lats, lons, timestamps,
                                  gps_noise_sigma = 4.0,
                                  accel_noise_sigma = 1.5,
                                  outlier_threshold_nis = 9.21) {
  n <- length(lats)
  if (n == 0L) {
    return(data.frame(lat = numeric(0), lon = numeric(0),
                      speed_mps = numeric(0), heading_deg = numeric(0),
                      is_outlier = logical(0)))
  }
  if (n == 1L) {
    return(data.frame(lat = lats, lon = lons,
                      speed_mps = 0.0, heading_deg = 0.0,
                      is_outlier = FALSE))
  }

  # Local metric tangent plane centered on first coordinate
  ref_lat <- lats[1L]
  ref_lon <- lons[1L]
  cos_ref <- cos(deg2rad(ref_lat))

  # Convert geographic to planar meters (East, North)
  geo_to_planar <- function(lt, ln) {
    e <- (ln - ref_lon) * DEG_TO_RAD * EARTH_RADIUS_MEAN * cos_ref
    n <- (lt - ref_lat) * DEG_TO_RAD * EARTH_RADIUS_MEAN
    c(e, n)
  }

  planar_to_geo <- function(e, n) {
    lt <- ref_lat + (n / EARTH_RADIUS_MEAN) * RAD_TO_DEG
    ln <- ref_lon + (e / (EARTH_RADIUS_MEAN * cos_ref)) * RAD_TO_DEG
    c(lat = lt, lon = ln)
  }

  # Initialize state: x = [e, n, v_e, v_n]^T
  p0 <- geo_to_planar(lats[1L], lons[1L])
  p1 <- geo_to_planar(lats[2L], lons[2L])
  dt0 <- max(0.1, as.numeric(timestamps[2L] - timestamps[1L]))
  v_e0 <- (p1[1] - p0[1]) / dt0
  v_n0 <- (p1[2] - p0[2]) / dt0

  x <- matrix(c(p0[1], p0[2], v_e0, v_n0), nrow = 4, ncol = 1)

  # Initial error covariance P
  P <- diag(c(gps_noise_sigma^2, gps_noise_sigma^2, 10.0^2, 10.0^2))

  # Measurement matrix H: maps state [e, n, v_e, v_n] to [e, n]
  H <- matrix(c(1, 0, 0, 0,
                0, 1, 0, 0), nrow = 2, ncol = 4, byrow = TRUE)

  # Measurement noise covariance R
  R <- diag(c(gps_noise_sigma^2, gps_noise_sigma^2))

  out_lats <- numeric(n)
  out_lons <- numeric(n)
  out_speeds <- numeric(n)
  out_headings <- numeric(n)
  out_is_outlier <- logical(n)

  # Record initial point
  out_lats[1L] <- lats[1L]
  out_lons[1L] <- lons[1L]
  out_speeds[1L] <- sqrt(v_e0^2 + v_n0^2)
  out_headings[1L] <- (atan2(v_e0, v_n0) * RAD_TO_DEG + 360.0) %% 360.0
  out_is_outlier[1L] <- FALSE

  for (k in 2:n) {
    dt <- max(0.01, as.numeric(timestamps[k] - timestamps[k - 1L]))

    # State transition matrix F
    F <- matrix(c(1, 0, dt, 0,
                  0, 1, 0, dt,
                  0, 0, 1, 0,
                  0, 0, 0, 1), nrow = 4, ncol = 4, byrow = TRUE)

    # Discrete process noise covariance Q based on piecewise continuous acceleration
    q_val <- accel_noise_sigma^2
    dt3 <- (dt^3) / 3.0
    dt2 <- (dt^2) / 2.0
    Q <- matrix(c(dt3 * q_val, 0, dt2 * q_val, 0,
                  0, dt3 * q_val, 0, dt2 * q_val,
                  dt2 * q_val, 0, dt * q_val, 0,
                  0, dt2 * q_val, 0, dt * q_val), nrow = 4, ncol = 4, byrow = TRUE)

    # Predict step
    x_pred <- F %*% x
    P_pred <- F %*% P %*% t(F) + Q

    # Measurement step
    meas <- geo_to_planar(lats[k], lons[k])
    z <- matrix(meas, nrow = 2, ncol = 1)

    # Innovation
    y <- z - H %*% x_pred
    S <- H %*% P_pred %*% t(H) + R
    S_inv <- solve(S)

    # Normalized Innovation Squared (NIS)
    nis <- as.numeric(t(y) %*% S_inv %*% y)

    if (nis > outlier_threshold_nis) {
      # Innovation breach: GPS glitch or satellite reflection
      # Update state with prediction only
      x <- x_pred
      P <- P_pred
      out_is_outlier[k] <- TRUE
    } else {
      # Kalman Gain
      K <- P_pred %*% t(H) %*% S_inv
      x <- x_pred + K %*% y
      P <- (diag(4) - K %*% H) %*% P_pred
      out_is_outlier[k] <- FALSE
    }

    # Extract smoothed coordinates
    geo_res <- planar_to_geo(x[1, 1], x[2, 1])
    out_lats[k] <- geo_res["lat"]
    out_lons[k] <- geo_res["lon"]

    v_e <- x[3, 1]
    v_n <- x[4, 1]
    spd <- sqrt(v_e^2 + v_n^2)
    heading <- (atan2(v_e, v_n) * RAD_TO_DEG + 360.0) %% 360.0

    out_speeds[k] <- spd
    out_headings[k] <- heading
  }

  data.frame(
    lat = out_lats,
    lon = out_lons,
    speed_mps = out_speeds,
    heading_deg = out_headings,
    is_outlier = out_is_outlier
  )
}
