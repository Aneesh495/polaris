# Polaris Map Matching: Numerically Stable Log-Space Viterbi Trellis Decoder
# Dynamic programming trellis finding Maximum A Posteriori (MAP) road state sequence

#' Compute Network Distance Between Two Candidate Projections
#'
#' @param graph Base polaris_graph
#' @param cand1 Candidate record at t-1 (edge_id, source, target, fraction)
#' @param cand2 Candidate record at t (edge_id, source, target, fraction)
#' @return Routing distance in meters
compute_candidate_network_distance <- function(graph, cand1, cand2) {
  e1 <- graph$get_edge(cand1$edge_id)
  e2 <- graph$get_edge(cand2$edge_id)

  if (cand1$edge_id == cand2$edge_id) {
    # Same road segment
    frac_diff <- cand2$fraction - cand1$fraction
    if (frac_diff >= 0.0) {
      return(frac_diff * e1$distance)
    } else if (!e1$oneway) {
      return(abs(frac_diff) * e1$distance)
    }
  }

  # Different edges: distance from cand1 to target of e1, plus shortest path
  # from target(e1) to source(e2), plus distance from source(e2) to cand2
  rem1 <- (1.0 - cand1$fraction) * e1$distance
  enter2 <- cand2$fraction * e2$distance

  if (e1$target == e2$source) {
    return(rem1 + enter2)
  }

  # Query shortest path between intermediate intersections
  path_res <- polaris_dijkstra(graph, source_id = e1$target, target_id = e2$source)
  if (path_res$status != "OK" || is.infinite(path_res$total_distance)) {
    return(Inf)
  }

  rem1 + path_res$total_distance + enter2
}

#' Log-Space Viterbi Trellis Decoder
#'
#' Evaluates the dynamic programming trellis over temporal layers of candidate states,
#' returning the globally optimal sequence of road segments maximizing joint posterior.
#'
#' @param graph Base polaris_graph
#' @param trellis_candidates List of length T, each containing list of candidate records
#' @param gps_coords List of polaris_coordinate objects of length T
#' @param gps_bearings Numeric vector of vehicle headings (optional)
#' @param timestamps Numeric vector of timestamps (optional)
#' @param sigma Measurement error std dev (default 4.07m)
#' @param beta Transition scale parameter (default 3.0m)
#' @return List with optimal_path (list of candidates), log_likelihood, matched_edges
#' @export
viterbi_trellis_decode <- function(graph, trellis_candidates, gps_coords,
                                   gps_bearings = NULL,
                                   timestamps = NULL,
                                   sigma = DEFAULT_GPS_SIGMA,
                                   beta = DEFAULT_TRANSITION_BETA) {
  T_steps <- length(trellis_candidates)
  if (T_steps == 0L) {
    return(list(optimal_path = list(), log_likelihood = -Inf, matched_edges = character(0)))
  }

  # Check for empty candidate layers
  valid_layers <- vapply(trellis_candidates, function(cands) length(cands) > 0L, logical(1))
  if (!all(valid_layers)) {
    # Some pings had no road candidate within radius
    # Fall back gracefully to best effort on non-empty layers
  }

  # Trellis matrices: V[t, state_idx] and Backpointer B[t, state_idx]
  V <- vector("list", T_steps)
  B <- vector("list", T_steps)

  # Layer 1: Prior + Emission
  cands_1 <- trellis_candidates[[1L]]
  K_1 <- length(cands_1)
  if (K_1 == 0L) {
    return(list(optimal_path = list(), log_likelihood = -Inf, matched_edges = character(0)))
  }

  V[[1L]] <- numeric(K_1)
  B[[1L]] <- integer(K_1)

  b1 <- if (!is.null(gps_bearings) && length(gps_bearings) >= 1) gps_bearings[1L] else NULL

  for (i in seq_len(K_1)) {
    c_i <- cands_1[[i]]
    log_em <- emission_log_prob_with_heading(
      c_i$distance_meters,
      gps_bearing = b1,
      road_bearing = c_i$road_bearing,
      is_oneway = c_i$oneway,
      sigma = sigma
    )
    V[[1L]][i] <- log_em # Uniform prior: ln(1/K) cancels out
  }

  # Layers 2 to T
  for (t in 2:T_steps) {
    cands_prev <- trellis_candidates[[t - 1L]]
    cands_curr <- trellis_candidates[[t]]
    K_prev <- length(cands_prev)
    K_curr <- length(cands_curr)

    if (K_curr == 0L) {
      V[[t]] <- numeric(0)
      B[[t]] <- integer(0)
      next
    }

    V[[t]] <- rep(-Inf, K_curr)
    B[[t]] <- integer(K_curr)

    # Great circle distance between pings
    d_gc <- haversine_distance(
      gps_coords[[t - 1L]]$lat, gps_coords[[t - 1L]]$lon,
      gps_coords[[t]]$lat, gps_coords[[t]]$lon
    )

    dt <- if (!is.null(timestamps) && length(timestamps) >= t) {
      as.numeric(timestamps[t] - timestamps[t - 1L])
    } else 0.0

    b_t <- if (!is.null(gps_bearings) && length(gps_bearings) >= t) gps_bearings[t] else NULL

    for (j in seq_len(K_curr)) {
      c_j <- cands_curr[[j]]
      log_em <- emission_log_prob_with_heading(
        c_j$distance_meters,
        gps_bearing = b_t,
        road_bearing = c_j$road_bearing,
        is_oneway = c_j$oneway,
        sigma = sigma
      )

      best_trans_val <- -Inf
      best_prev_idx <- 1L

      for (i in seq_len(K_prev)) {
        c_i <- cands_prev[[i]]
        d_route <- compute_candidate_network_distance(graph, c_i, c_j)

        log_tr <- if (dt > 0.0) {
          transition_log_prob_temporal(d_route, d_gc, dt = dt, beta = beta)
        } else {
          transition_log_prob(d_route, d_gc, beta = beta)
        }

        total_cand <- V[[t - 1L]][i] + log_tr
        if (total_cand > best_trans_val) {
          best_trans_val <- total_cand
          best_prev_idx <- i
        }
      }

      V[[t]][j] <- best_trans_val + log_em
      B[[t]][j] <- best_prev_idx
    }
  }

  # Backtrack MAP sequence
  final_scores <- V[[T_steps]]
  if (length(final_scores) == 0L || all(is.infinite(final_scores))) {
    return(list(optimal_path = list(), log_likelihood = -Inf, matched_edges = character(0)))
  }

  best_final_idx <- which.max(final_scores)
  best_log_likelihood <- final_scores[best_final_idx]

  optimal_seq <- vector("list", T_steps)
  curr_idx <- best_final_idx

  for (t in T_steps:1) {
    optimal_seq[[t]] <- trellis_candidates[[t]][[curr_idx]]
    if (t > 1) {
      curr_idx <- B[[t]][curr_idx]
      if (is.na(curr_idx) || curr_idx < 1L) curr_idx <- 1L
    }
  }

  # Extract unique matched edge sequence
  matched_edges <- character(0)
  for (cand in optimal_seq) {
    if (!is.null(cand) && !is.null(cand$edge_id)) {
      if (length(matched_edges) == 0L || matched_edges[length(matched_edges)] != cand$edge_id) {
        matched_edges <- c(matched_edges, cand$edge_id)
      }
    }
  }

  list(
    optimal_path = optimal_seq,
    log_likelihood = best_log_likelihood,
    matched_edges = matched_edges
  )
}
