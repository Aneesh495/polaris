# Polaris Map Matching: End-to-End Autonomous Trajectory Matcher
# Snaps noisy GPS traces to ground-truth road network topology with gap handling

#' Match GPS Trajectory to Road Network
#'
#' Orchestrates candidate road discovery, Kalman pre-filtering, and Viterbi MAP
#' sequence decoding to snap noisy GPS sensor telemetry to the road graph.
#'
#' @param graph Base polaris_graph object
#' @param trace Data frame with lat, lon, and optional timestamp, speed, bearing
#' @param search_radius_meters Max spatial candidate radius in meters (default 50m)
#' @param max_candidates Maximum candidate segments per observation (default 8)
#' @param use_kalman Logical, whether to pre-filter GPS jitter via Extended Kalman Filter
#' @param max_gap_seconds Temporal threshold to split disconnected trace segments (default 120s)
#' @param sigma Measurement error std dev (default 4.07m)
#' @param beta Transition scale parameter (default 3.0m)
#' @return S3 object of class polaris_matched_trace
#' @export
polaris_map_match <- function(graph, trace,
                              search_radius_meters = 50.0,
                              max_candidates = 8L,
                              use_kalman = FALSE,
                              max_gap_seconds = 120.0,
                              sigma = DEFAULT_GPS_SIGMA,
                              beta = DEFAULT_TRANSITION_BETA) {
  if (nrow(trace) == 0L) {
    return(structure(list(points = list(), edges = character(0), status = "EMPTY_TRACE"),
                     class = "polaris_matched_trace"))
  }

  has_time <- "timestamp" %in% names(trace)
  has_bearing <- "bearing" %in% names(trace)

  raw_lats <- as.numeric(trace$lat)
  raw_lons <- as.numeric(trace$lon)
  raw_times <- if (has_time) as.numeric(trace$timestamp) else seq_along(raw_lats)
  raw_bearings <- if (has_bearing) as.numeric(trace$bearing) else rep(NA_real_, length(raw_lats))

  # Optional Kalman filter pass
  if (use_kalman && length(raw_lats) >= 2) {
    kf_res <- polaris_kalman_filter(raw_lats, raw_lons, raw_times)
    proc_lats <- kf_res$lat
    proc_lons <- kf_res$lon
    proc_bearings <- kf_res$heading_deg
  } else {
    proc_lats <- raw_lats
    proc_lons <- raw_lons
    proc_bearings <- raw_bearings
  }

  n_points <- length(proc_lats)

  # Detect temporal gaps and split into independent sub-trajectories
  split_indices <- 1L
  if (n_points > 1) {
    for (i in 2:n_points) {
      if ((raw_times[i] - raw_times[i - 1L]) > max_gap_seconds) {
        split_indices <- c(split_indices, i)
      }
    }
  }
  split_indices <- c(split_indices, n_points + 1L)

  all_matched_points <- list()
  all_matched_edges <- character(0)
  total_log_likelihood <- 0.0

  for (seg_idx in seq_len(length(split_indices) - 1L)) {
    start_i <- split_indices[seg_idx]
    end_i <- split_indices[seg_idx + 1L] - 1L
    seg_len <- end_i - start_i + 1L

    if (seg_len <= 0L) next

    seg_lats <- proc_lats[start_i:end_i]
    seg_lons <- proc_lons[start_i:end_i]
    seg_times <- raw_times[start_i:end_i]
    seg_bearings <- proc_bearings[start_i:end_i]

    # Gather candidates for each point in sub-segment
    trellis_cands <- vector("list", seg_len)
    gps_coords <- vector("list", seg_len)

    for (k in seq_len(seg_len)) {
      c_lt <- seg_lats[k]
      c_ln <- seg_lons[k]
      c_brg <- seg_bearings[k]
      gps_coords[[k]] <- polaris_coordinate(c_lt, c_ln)

      cands <- find_candidate_segments(
        graph = graph,
        lat = c_lt,
        lon = c_ln,
        gps_bearing = c_brg,
        max_radius_meters = search_radius_meters,
        max_candidates = max_candidates
      )
      trellis_cands[[k]] <- cands
    }

    # Run Viterbi decoder
    viterbi_res <- viterbi_trellis_decode(
      graph = graph,
      trellis_candidates = trellis_cands,
      gps_coords = gps_coords,
      gps_bearings = seg_bearings,
      timestamps = seg_times,
      sigma = sigma,
      beta = beta
    )

    if (length(viterbi_res$optimal_path) > 0L) {
      for (k in seq_along(viterbi_res$optimal_path)) {
        cand <- viterbi_res$optimal_path[[k]]
        if (!is.null(cand)) {
          all_matched_points[[length(all_matched_points) + 1L]] <- list(
            raw_lat = seg_lats[k],
            raw_lon = seg_lons[k],
            snapped_lat = cand$proj_lat,
            snapped_lon = cand$proj_lon,
            edge_id = cand$edge_id,
            distance_meters = cand$distance_meters
          )
        }
      }
      all_matched_edges <- c(all_matched_edges, viterbi_res$matched_edges)
      if (!is.infinite(viterbi_res$log_likelihood)) {
        total_log_likelihood <- total_log_likelihood + viterbi_res$log_likelihood
      }
    }
  }

  structure(
    list(
      matched_points = all_matched_points,
      matched_edges = unique(all_matched_edges),
      log_likelihood = total_log_likelihood,
      total_pings = n_points,
      status = if (length(all_matched_points) > 0) "SUCCESS" else "NO_MATCH"
    ),
    class = "polaris_matched_trace"
  )
}

#' Print method for polaris_matched_trace
#' @export
print.polaris_matched_trace <- function(x, ...) {
  cat(sprintf("<polaris_matched_trace status=%s pings=%d matched=%d edges=%d log_lik=%.2f>\n",
              x$status, x$total_pings, length(x$matched_points), length(x$matched_edges), x$log_likelihood))
  invisible(x)
}
