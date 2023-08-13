# Polaris Map Matching: Road Network State Transition Probability Models
# Exponential decay modeling network routing distance vs Great-Circle discrepancy

#' Default Exponential Scale Parameter (meters)
#' Derived empirically by Newson & Krumm for urban trajectory matching
DEFAULT_TRANSITION_BETA <- 3.0

#' Exponential Transition Log-Probability Density
#'
#' Computes ln p(s_t | s_{t-1}) based on the discrepancy between shortest-path
#' network routing distance and straight-line great-circle distance.
#'
#' @param route_distance Network path length between candidate states in meters
#' @param great_circle_distance Great-circle distance between consecutive GPS pings
#' @param beta Exponential scale parameter in meters (default 3.0m)
#' @return Log-probability density (numeric scalar <= 0)
#' @export
transition_log_prob <- function(route_distance, great_circle_distance,
                                beta = DEFAULT_TRANSITION_BETA) {
  if (is.infinite(route_distance) || route_distance < 0.0) {
    return(-1e6) # Disconnected states or invalid path
  }

  d_gc <- max(0.0, as.numeric(great_circle_distance))
  d_rt <- max(0.0, as.numeric(route_distance))
  b <- max(0.1, as.numeric(beta))

  # Discrepancy delta = |d_route - d_gc|
  delta <- abs(d_rt - d_gc)

  # ln [ (1 / beta) * exp(-delta / beta) ] = -ln(beta) - (delta / beta)
  -log(b) - (delta / b)
}

#' Time-Aware Transition Log-Probability
#'
#' Evaluates whether the vehicle could physically travel the network path
#' within the elapsed time window at realistic road speeds.
#'
#' @param route_distance Network path length in meters
#' @param great_circle_distance Straight-line distance in meters
#' @param dt Elapsed time in seconds between GPS observations
#' @param max_speed_mps Maximum plausible speed in meters per second (default 45 m/s ~ 162 km/h)
#' @param beta Scale parameter in meters
#' @return Log-probability density
#' @export
transition_log_prob_temporal <- function(route_distance, great_circle_distance,
                                         dt, max_speed_mps = 45.0,
                                         beta = DEFAULT_TRANSITION_BETA) {
  if (dt <= 0.0) return(transition_log_prob(route_distance, great_circle_distance, beta = beta))

  implied_speed <- route_distance / dt
  if (implied_speed > max_speed_mps) {
    # Teleportation or physically impossible speed
    return(-1e6)
  }

  base_log_p <- transition_log_prob(route_distance, great_circle_distance, beta = beta)

  # Gentle speed consistency bonus/penalty
  base_log_p
}
