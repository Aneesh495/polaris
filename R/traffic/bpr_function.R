# Polaris Traffic Assignment: Bureau of Public Roads (BPR) Volume-Delay Functions
# Models non-linear link travel time congestion and convex Beckmann integrals

DEFAULT_BPR_ALPHA <- 0.15
DEFAULT_BPR_BETA <- 4.0

#' Bureau of Public Roads (BPR) Congestion Delay Function
#'
#' Computes link travel time given current vehicle flow volume and design capacity:
#' t(x) = t_0 * [1 + alpha * (x / capacity)^beta]
#'
#' @param free_flow_time Free-flow travel time in seconds
#' @param flow Current traffic flow volume (vehicles/hour)
#' @param capacity Roadway design capacity (vehicles/hour)
#' @param alpha BPR alpha parameter (default 0.15)
#' @param beta BPR beta parameter (default 4.0)
#' @return Congested travel time in seconds
#' @export
bpr_travel_time <- function(free_flow_time, flow, capacity,
                            alpha = DEFAULT_BPR_ALPHA,
                            beta = DEFAULT_BPR_BETA) {
  t0 <- max(0.1, as.numeric(free_flow_time))
  x <- max(0.0, as.numeric(flow))
  c_val <- max(1.0, as.numeric(capacity))

  # Congestion ratio
  v_c <- x / c_val
  t0 * (1.0 + alpha * (v_c^beta))
}

#' Beckmann Objective Integral Contribution
#'
#' Computes the definite integral of the BPR travel time function from 0 to flow:
#' Integral_0^x t(w) dw = t_0 * [x + (alpha / (beta + 1)) * (x^(beta + 1) / capacity^beta)]
#'
#' @export
bpr_integral <- function(free_flow_time, flow, capacity,
                         alpha = DEFAULT_BPR_ALPHA,
                         beta = DEFAULT_BPR_BETA) {
  t0 <- max(0.1, as.numeric(free_flow_time))
  x <- max(0.0, as.numeric(flow))
  c_val <- max(1.0, as.numeric(capacity))

  t0 * (x + (alpha / (beta + 1.0)) * ((x^(beta + 1.0)) / (c_val^beta)))
}

#' BPR Function Analytical Derivative
#'
#' First derivative dt/dx = t_0 * alpha * beta * (x^(beta - 1) / capacity^beta)
#'
#' @export
bpr_derivative <- function(free_flow_time, flow, capacity,
                           alpha = DEFAULT_BPR_ALPHA,
                           beta = DEFAULT_BPR_BETA) {
  t0 <- max(0.1, as.numeric(free_flow_time))
  x <- max(0.0, as.numeric(flow))
  c_val <- max(1.0, as.numeric(capacity))

  if (x == 0.0) return(0.0)
  t0 * alpha * beta * ((x^(beta - 1.0)) / (c_val^beta))
}
