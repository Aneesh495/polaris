# Polaris Public Transit: Timetable Network Graph & RAPTOR Data Models
# Compiles GTFS feeds into high-speed route patterns, stop indices, and footpaths

#' Build RAPTOR Timetable Network from GTFS Feed
#'
#' Organizes trips into canonical route patterns (distinct stop sequences)
#' and builds inverted stop-to-routes lookup maps.
#'
#' @param feed polaris_gtfs_feed object
#' @param max_transfer_walk_meters Max walking distance for synthesized footpaths (default 500m)
#' @param walk_speed_mps Walking speed in m/s (default 1.2 m/s ~ 4.3 km/h)
#' @return An environment of class polaris_raptor_network
#' @export
build_raptor_network <- function(feed, max_transfer_walk_meters = 500.0,
                                walk_speed_mps = 1.2) {
  cat("[polaris-raptor] Compiling GTFS timetable into route patterns...\n")

  # 1. Map stops
  stop_ids <- unique(feed$stops$stop_id)
  n_stops <- length(stop_ids)
  stop_to_idx <- setNames(seq_len(n_stops), stop_ids)
  idx_to_stop <- stop_ids

  # Stop coordinates
  stop_coords <- list()
  for (i in seq_len(nrow(feed$stops))) {
    s_id <- feed$stops$stop_id[i]
    stop_coords[[s_id]] <- polaris_coordinate(feed$stops$lat[i], feed$stops$lon[i])
  }

  # 2. Group trips by stop sequence signature
  # trip_id -> list of stop_ids
  trip_stops <- split(feed$stop_times$stop_id, feed$stop_times$trip_id)
  trip_deps  <- split(feed$stop_times$departure_time, feed$stop_times$trip_id)
  trip_arrs  <- split(feed$stop_times$arrival_time, feed$stop_times$trip_id)

  # Map trip signature to route pattern
  patterns <- list() # pattern_id -> list(stops = c(...), trip_ids = c(...))
  pattern_sig_to_id <- new.env(hash = TRUE, parent = emptyenv())
  pattern_counter <- 0L

  for (t_id in names(trip_stops)) {
    stops_seq <- trip_stops[[t_id]]
    sig <- paste(stops_seq, collapse = ">")

    pat_id <- pattern_sig_to_id[[sig]]
    if (is.null(pat_id)) {
      pattern_counter <- pattern_counter + 1L
      pat_id <- sprintf("route_%d", pattern_counter)
      pattern_sig_to_id[[sig]] <- pat_id
      patterns[[pat_id]] <- list(
        id = pat_id,
        stops = stops_seq,
        trip_ids = character(0)
      )
    }
    patterns[[pat_id]]$trip_ids <- c(patterns[[pat_id]]$trip_ids, t_id)
  }

  cat(sprintf("[polaris-raptor] Identified %d canonical route patterns across %d trips.\n",
              length(patterns), length(trip_stops)))

  # 3. For each route pattern, sort trips by departure time at the first stop
  for (r_id in names(patterns)) {
    t_ids <- patterns[[r_id]]$trip_ids
    first_deps <- integer(length(t_ids))
    for (i in seq_along(t_ids)) {
      first_deps[i] <- trip_deps[[t_ids[i]]][1L]
    }
    ord <- order(first_deps)
    patterns[[r_id]]$trip_ids <- t_ids[ord]
  }

  # 4. Inverted index: stop_id -> list of route pattern IDs
  stop_to_routes <- vector("list", n_stops)
  names(stop_to_routes) <- stop_ids
  for (r_id in names(patterns)) {
    for (s_id in patterns[[r_id]]$stops) {
      stop_to_routes[[s_id]] <- c(stop_to_routes[[s_id]], r_id)
    }
  }
  for (s_id in stop_ids) {
    stop_to_routes[[s_id]] <- unique(stop_to_routes[[s_id]])
  }

  # 5. Build footpaths (transfers)
  footpaths <- vector("list", n_stops)
  names(footpaths) <- stop_ids

  # Explicit transfers from feed
  if (nrow(feed$transfers) > 0) {
    for (i in seq_len(nrow(feed$transfers))) {
      from_s <- feed$transfers$from_stop_id[i]
      to_s <- feed$transfers$to_stop_id[i]
      t_time <- as.integer(feed$transfers$min_transfer_time[i])
      if (from_s %in% stop_ids && to_s %in% stop_ids) {
        footpaths[[from_s]][[length(footpaths[[from_s]]) + 1L]] <- list(
          to_stop = to_s,
          duration_sec = t_time
        )
      }
    }
  }

  # Synthesize geographic walking footpaths between stops within max_transfer_walk_meters
  if (n_stops > 1) {
    for (i in seq_len(n_stops - 1L)) {
      s1 <- stop_ids[i]
      c1 <- stop_coords[[s1]]
      for (j in seq(i + 1L, n_stops)) {
        s2 <- stop_ids[j]
        c2 <- stop_coords[[s2]]
        d_m <- haversine_distance(c1$lat, c1$lon, c2$lat, c2$lon)
        if (d_m <= max_transfer_walk_meters) {
          walk_sec <- as.integer(ceiling(d_m / walk_speed_mps))
          # Bidirectional footpath
          footpaths[[s1]][[length(footpaths[[s1]]) + 1L]] <- list(to_stop = s2, duration_sec = walk_sec)
          footpaths[[s2]][[length(footpaths[[s2]]) + 1L]] <- list(to_stop = s1, duration_sec = walk_sec)
        }
      }
    }
  }

  net <- new.env(parent = emptyenv())
  net$stop_ids <- stop_ids
  net$stop_to_idx <- stop_to_idx
  net$idx_to_stop <- idx_to_stop
  net$stop_coords <- stop_coords
  net$patterns <- patterns
  net$stop_to_routes <- stop_to_routes
  net$footpaths <- footpaths
  net$trip_stops <- trip_stops
  net$trip_deps <- trip_deps
  net$trip_arrs <- trip_arrs

  structure(net, class = "polaris_raptor_network")
}
