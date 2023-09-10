# Polaris Public Transit: Range RAPTOR Departure Window Profile Queries
# Computes Pareto-optimal journeys across arbitrary departure time windows

#' Range RAPTOR Profile Query
#'
#' Evaluates RAPTOR queries across an entire departure window (e.g. 07:00 to 09:00),
#' uncovering frequency-based wait times and non-dominated departure options.
#'
#' @param raptor_net polaris_raptor_network object
#' @param origin_stop_id Departure transit stop ID
#' @param target_stop_id Arrival transit stop ID
#' @param start_time_sec Window start in seconds past midnight
#' @param end_time_sec Window end in seconds past midnight
#' @param step_minutes Sampling step interval in minutes (default 10 mins)
#' @param max_rounds Max transfers to explore per query
#' @return List of non-dominated journey profiles across the departure window
#' @export
polaris_range_raptor <- function(raptor_net, origin_stop_id, target_stop_id,
                                 start_time_sec, end_time_sec,
                                 step_minutes = 10L, max_rounds = 4L) {
  step_sec <- as.integer(max(1L, step_minutes) * 60L)
  dep_times <- seq(start_time_sec, end_time_sec, by = step_sec)

  all_itineraries <- list()

  for (dep_t in dep_times) {
    res <- polaris_raptor(
      raptor_net = raptor_net,
      origin_stop_id = origin_stop_id,
      target_stop_id = target_stop_id,
      departure_time_sec = dep_t,
      max_rounds = max_rounds
    )
    if (length(res) > 0) {
      all_itineraries <- c(all_itineraries, res)
    }
  }

  if (length(all_itineraries) == 0L) {
    return(list())
  }

  # Filter global Pareto dominance:
  # Itinerary A dominates B if arr(A) <= arr(B) AND xfer(A) <= xfer(B) AND dep(A) >= dep(B)
  is_dominated <- logical(length(all_itineraries))

  for (i in seq_along(all_itineraries)) {
    a <- all_itineraries[[i]]
    a_dep <- gtfs_time_to_seconds(a$departure_time)
    a_arr <- gtfs_time_to_seconds(a$arrival_time)
    a_xfer <- a$transfers

    for (j in seq_along(all_itineraries)) {
      if (i == j || is_dominated[j]) next
      b <- all_itineraries[[j]]
      b_dep <- gtfs_time_to_seconds(b$departure_time)
      b_arr <- gtfs_time_to_seconds(b$arrival_time)
      b_xfer <- b$transfers

      if (b_dep >= a_dep && b_arr <= a_arr && b_xfer <= a_xfer &&
          (b_dep > a_dep || b_arr < a_arr || b_xfer < a_xfer)) {
        is_dominated[i] <- TRUE
        break
      }
    }
  }

  all_itineraries[!is_dominated]
}
