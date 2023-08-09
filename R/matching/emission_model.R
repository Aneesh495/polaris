# Polaris Map Matching: GPS Sensor Observation Emission Models
# Gaussian and Student-t emission probability densities for perpendicular projection errors

#' Standard GPS Measurement Standard Deviation (meters)
#' Typical mobile GPS error standard deviation under open sky
DEFAULT_GPS_SIGMA <- 4.07

#' Gaussian Emission Log-Probability Density
#'
#' Computes ln p(z | s) where z is the GPS observation and s is a candidate road segment.
#' Error is the perpendicular distance in meters from GPS ping to segment projection.
#'
#' @param distance_meters Perpendicular distance in meters
#' @param sigma Measurement standard deviation in meters (default 4.07m)
#' @return Log-probability density (numeric scalar <= 0)
#' @export
emission_log_prob_gaussian <- function(distance_meters, sigma = DEFAULT_GPS_SIGMA) {
  d <- max(0.0, as.numeric(distance_meters))
  sig <- max(0.1, as.numeric(sigma))

  # ln [ 1 / (sqrt(2 * pi) * sig) * exp(-d^2 / (2 * sig^2)) ]
  # = -ln(sig) - 0.5 * ln(2 * pi) - (d^2 / (2 * sig^2))
  -log(sig) - 0.5 * log(2.0 * pi) - (d * d) / (2.0 * sig * sig)
}

#' Student-t Emission Log-Probability Density
#'
#' Heavy-tailed distribution robust to severe urban multipath reflections
#' and GPS satellite clock jumps.
#'
#' @param distance_meters Perpendicular distance in meters
#' @param df Degrees of freedom (default 3.0 for heavy tails)
#' @param scale Scale parameter in meters (default 4.0m)
#' @return Log-probability density
#' @export
emission_log_prob_student_t <- function(distance_meters, df = 3.0, scale = 4.0) {
  d <- max(0.0, as.numeric(distance_meters))
  nu <- max(1.0, as.numeric(df))
  s <- max(0.1, as.numeric(scale))

  # Standard Student-t log-density:
  # lgamma((nu + 1)/2) - lgamma(nu/2) - 0.5*ln(nu*pi) - ln(s) - ((nu+1)/2) * ln(1 + (d/s)^2 / nu)
  lgamma((nu + 1.0) / 2.0) - lgamma(nu / 2.0) - 0.5 * log(nu * pi) -
    log(s) - ((nu + 1.0) / 2.0) * log(1.0 + (d * d) / (nu * s * s))
}

#' Combined Emission Density with Heading Alignment
#'
#' Weights spatial distance error alongside compass bearing discrepancy.
#' If vehicle heading differs from road direction by > 90 degrees on a oneway road,
#' applies a strong penalty.
#'
#' @param distance_meters Perpendicular distance in meters
#' @param gps_bearing Vehicle heading from GPS in degrees [0, 360)
#' @param road_bearing Compass direction of candidate road segment [0, 360)
#' @param is_oneway Logical indicating if road is one-way
#' @param sigma Distance standard deviation
#' @param heading_weight Weight factor for heading alignment (0 to 1)
#' @return Log-probability density
#' @export
emission_log_prob_with_heading <- function(distance_meters,
                                           gps_bearing = NULL,
                                           road_bearing = NULL,
                                           is_oneway = FALSE,
                                           sigma = DEFAULT_GPS_SIGMA,
                                           heading_weight = 0.3) {
  base_log_p <- emission_log_prob_gaussian(distance_meters, sigma = sigma)
  if (is.null(gps_bearing) || is.null(road_bearing) || is.na(gps_bearing) || is.na(road_bearing)) {
    return(base_log_p)
  }

  angle_diff <- abs(((gps_bearing - road_bearing + 180.0) %% 360.0) - 180.0)

  if (is_oneway && angle_diff > 90.0) {
    # Heading opposite to oneway traffic direction
    return(-1e6)
  }

  # Angular penalty modeled as Von Mises / Gaussian on angular error
  # sigma_angle ~ 25 degrees
  sigma_angle <- 25.0
  angle_log_p <- - (angle_diff * angle_diff) / (2.0 * sigma_angle * sigma_angle)

  base_log_p + (heading_weight * angle_log_p)
}
