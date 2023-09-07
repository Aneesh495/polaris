# Polaris Public Transit: RAPTOR Round-Based Public Transit Routing
# Multi-criteria Pareto-optimal journey planning: arrival time vs transfer count

#' RAPTOR Multi-Criteria Journey Planning
#'
#' Computes the complete Pareto-optimal frontier of transit itineraries
#' without edge weights, strictly trading off arrival time against transfer count.
#'
#' @param raptor_net polaris_raptor_network object from build_raptor_network()
#' @param origin_stop_id Character identifier of departure transit stop
#' @param target_stop_id Character identifier of destination transit stop
#' @param departure_time_sec Departure time in seconds past midnight (e.g. 28800 for 08:00:00)
#' @param max_rounds Maximum trip legs / rounds to explore (default 4 rounds = 3 transfers)
#' @return List of Pareto-optimal itineraries
#' @export
polaris_raptor <- function(raptor_net, origin_stop_id, target_stop_id,
                           departure_time_sec, max_rounds = 4L) {
  s_orig <- as.character(origin_stop_id)
  s_tgt <- as.character(target_stop_id)

  orig_idx <- raptor_net$stop_to_idx[[s_orig]]
  tgt_idx <- raptor_net$stop_to_idx[[s_tgt]]

  if (is.null(orig_idx)) stop(sprintf("polaris_raptor: origin stop '%s' not found", s_orig))
  if (is.null(tgt_idx)) stop(sprintf("polaris_raptor: target stop '%s' not found", s_tgt))

  n_stops <- length(raptor_net$stop_ids)
  max_k <- as.integer(max(1L, min(8L, max_rounds)))

  # Tau[k, stop_idx]: earliest arrival time at stop in round k
  Tau <- matrix(Inf, nrow = max_k + 1L, ncol = n_stops)
  # Tau_best[stop_idx]: best arrival time across all rounds
  Tau_best <- rep(Inf, n_stops)

  # Parent pointers for path reconstruction
  # parent_info[[k]][[stop_idx]] = list(type='trip'/'walk', from_stop, trip_id, board_time, alight_time)
  parent_info <- vector("list", max_k + 1L)
  for (k in seq_len(max_k + 1L)) {
    parent_info[[k]] <- vector("list", n_stops)
  }

  # Round 0: Origin initialization
  Tau[1L, orig_idx] <- departure_time_sec
  Tau_best[orig_idx] <- departure_time_sec

  # Relax footpaths from origin
  orig_footpaths <- raptor_net$footpaths[[s_orig]]
  if (!is.null(orig_footpaths)) {
    for (fp in orig_footpaths) {
      fp_idx <- raptor_net$stop_to_idx[[fp$to_stop]]
      arr_fp <- departure_time_sec + fp$duration_sec
      if (arr_fp < Tau[1L, fp_idx]) {
        Tau[1L, fp_idx] <- arr_fp
        Tau_best[fp_idx] <- arr_fp
        parent_info[[1L]][[fp_idx]] <- list(
          type = "walk",
          from_stop = s_orig,
          to_stop = fp$to_stop,
          duration_sec = fp$duration_sec
        )
      }
    }
  }

  # Marked stops from round 0
  marked_stops <- rep(FALSE, n_stops)
  marked_stops[orig_idx] <- TRUE
  if (!is.null(orig_footpaths)) {
    for (fp in orig_footpaths) {
      marked_stops[raptor_net$stop_to_idx[[fp$to_stop]]] <- TRUE
    }
  }

  # Main RAPTOR Rounds
  for (k in 1:max_k) {
    k_curr <- k + 1L
    k_prev <- k

    # Copy previous round arrival times as upper bounds
    Tau[k_curr, ] <- Tau[k_prev, ]

    # Step 1: Accumulate routes serving any marked stop
    marked_routes <- character(0)
    marked_indices <- which(marked_stops)
    if (length(marked_indices) == 0L) break

    for (s_idx in marked_indices) {
      s_id <- raptor_net$idx_to_stop[s_idx]
      r_ids <- raptor_net$stop_to_routes[[s_id]]
      if (length(r_ids) > 0) {
        marked_routes <- c(marked_routes, r_ids)
      }
    }
    marked_routes <- unique(marked_routes)
    marked_stops[] <- FALSE

    # Step 2: Explore each marked route pattern
    for (r_id in marked_routes) {
      pattern <- raptor_net$patterns[[r_id]]
      p_stops <- pattern$stops
      p_trips <- pattern$trip_ids

      curr_trip_id <- NULL
      board_stop_id <- NULL
      board_time_sec <- 0L

      for (pos in seq_along(p_stops)) {
        p_id <- p_stops[pos]
        p_idx <- raptor_net$stop_to_idx[[p_id]]

        # Can we alight from current trip at p_id?
        if (!is.null(curr_trip_id)) {
          arr_time <- raptor_net$trip_arrs[[curr_trip_id]][pos]
          if (arr_time < min(Tau[k_curr, p_idx], Tau_best[tgt_idx])) {
            Tau[k_curr, p_idx] <- arr_time
            Tau_best[p_idx] <- min(Tau_best[p_idx], arr_time)
            marked_stops[p_idx] <- TRUE

            parent_info[[k_curr]][[p_idx]] <- list(
              type = "trip",
              trip_id = curr_trip_id,
              route_id = r_id,
              from_stop = board_stop_id,
              to_stop = p_id,
              board_time = board_time_sec,
              alight_time = arr_time
            )
          }
        }

        # Can we board an earlier trip departing p_id at or after Tau[k_prev, p_idx]?
        t_prev_arr <- Tau[k_prev, p_idx]
        if (!is.infinite(t_prev_arr)) {
          # Scan trips to find earliest departure
          for (t_cand in p_trips) {
            dep_cand <- raptor_net$trip_deps[[t_cand]][pos]
            if (dep_cand >= t_prev_arr) {
              # If we have no trip yet, or this trip departs earlier than curr_trip at pos
              if (is.null(curr_trip_id) || dep_cand < raptor_net$trip_deps[[curr_trip_id]][pos]) {
                curr_trip_id <- t_cand
                board_stop_id <- p_id
                board_time_sec <- dep_cand
              }
              break
            }
          }
        }
      }
    }

    # Step 3: Relax footpaths from stops improved in this round
    improved_stops <- which(marked_stops)
    for (p_idx in improved_stops) {
      p_id <- raptor_net$idx_to_stop[p_idx]
      p_arr <- Tau[k_curr, p_idx]
      footpaths_p <- raptor_net$footpaths[[p_id]]

      if (!is.null(footpaths_p)) {
        for (fp in footpaths_p) {
          fp_idx <- raptor_net$stop_to_idx[[fp$to_stop]]
          arr_fp <- p_arr + fp$duration_sec
          if (arr_fp < min(Tau[k_curr, fp_idx], Tau_best[tgt_idx])) {
            Tau[k_curr, fp_idx] <- arr_fp
            Tau_best[fp_idx] <- min(Tau_best[fp_idx], arr_fp)
            marked_stops[fp_idx] <- TRUE

            parent_info[[k_curr]][[fp_idx]] <- list(
              type = "walk",
              from_stop = p_id,
              to_stop = fp$to_stop,
              duration_sec = fp$duration_sec
            )
          }
        }
      }
    }
  }

  # Step 4: Extract Pareto frontier of itineraries
  itineraries <- list()
  best_arr_so_far <- Inf

  for (k in 1:max_k) {
    k_curr <- k + 1L
    arr_k <- Tau[k_curr, tgt_idx]

    if (!is.infinite(arr_k) && arr_k < best_arr_so_far) {
      best_arr_so_far <- arr_k

      # Backtrack journey
      legs <- list()
      curr_stop_id <- s_tgt
      curr_k <- k_curr

      while (curr_stop_id != s_orig && curr_k >= 1L) {
        c_idx <- raptor_net$stop_to_idx[[curr_stop_id]]
        p_edge <- parent_info[[curr_k]][[c_idx]]
        if (is.null(p_edge)) break

        legs <- c(list(p_edge), legs)
        curr_stop_id <- p_edge$from_stop

        if (p_edge$type == "trip") {
          curr_k <- curr_k - 1L
        }
      }

      itineraries[[length(itineraries) + 1L]] <- list(
        transfers = k - 1L,
        departure_time = seconds_to_gtfs_time(departure_time_sec),
        arrival_time = seconds_to_gtfs_time(arr_k),
        duration_minutes = (arr_k - departure_time_sec) / 60.0,
        legs = legs
      )
    }
  }

  itineraries
}
