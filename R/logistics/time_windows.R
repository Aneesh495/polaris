# Polaris Logistics: Vehicle Routing with Time Windows (VRPTW)
# Schedule timeline verification, dwell times, and waiting time evaluation

#' Evaluate Time Window Schedule for a Route
#'
#' Simulates transit and dwell timeline along a vehicle tour, validating
#' whether customer ready times and due dates are satisfied.
#'
#' @param tour Sequence of customer IDs (excluding depot)
#' @param problem polaris_vrp_problem object
#' @param departure_time_sec Vehicle dispatch time from depot (seconds past midnight)
#' @param transit_speed_mps Vehicle travel speed in meters per second (default 11.1 m/s ~ 40 km/h)
#' @return List of schedule stops, total duration, waiting time, and feasibility boolean
#' @export
evaluate_vrptw_schedule <- function(tour, problem,
                                    departure_time_sec = 28800.0,
                                    transit_speed_mps = 11.1) {
  depot <- problem$depot
  d_mat <- problem$distance_matrix

  # Customer lookup
  cust_map <- new.env(hash = TRUE, parent = emptyenv())
  for (c in problem$customers) cust_map[[c$id]] <- c

  current_time <- departure_time_sec
  total_wait <- 0.0
  is_feasible <- TRUE

  stops_schedule <- list()
  stops_schedule[[1L]] <- list(
    stop_id = depot$id,
    arrival_time = departure_time_sec,
    wait_time = 0.0,
    departure_time = departure_time_sec,
    feasible = TRUE
  )

  prev_id <- depot$id

  for (cust_id in tour) {
    cust <- cust_map[[cust_id]]
    leg_dist <- d_mat[prev_id, cust_id]
    transit_sec <- leg_dist / transit_speed_mps

    arrival_t <- current_time + transit_sec
    wait_t <- max(0.0, cust$ready_time - arrival_t)
    service_start <- max(arrival_t, cust$ready_time)
    departure_t <- service_start + cust$service_time

    # Check due time constraint
    node_feasible <- (arrival_t <= cust$due_time)
    if (!node_feasible) is_feasible <- FALSE

    total_wait <- total_wait + wait_t
    current_time <- departure_t

    stops_schedule[[length(stops_schedule) + 1L]] <- list(
      stop_id = cust_id,
      arrival_time = arrival_t,
      wait_time = wait_t,
      departure_time = departure_t,
      feasible = node_feasible
    )

    prev_id <- cust_id
  }

  # Return leg to depot
  return_dist <- d_mat[prev_id, depot$id]
  return_transit <- return_dist / transit_speed_mps
  depot_return_t <- current_time + return_transit

  if (depot_return_t > depot$due_time) {
    is_feasible <- FALSE
  }

  stops_schedule[[length(stops_schedule) + 1L]] <- list(
    stop_id = depot$id,
    arrival_time = depot_return_t,
    wait_time = 0.0,
    departure_time = depot_return_t,
    feasible = (depot_return_t <= depot$due_time)
  )

  list(
    schedule = stops_schedule,
    total_duration_sec = depot_return_t - departure_time_sec,
    total_wait_sec = total_wait,
    is_feasible = is_feasible
  )
}
