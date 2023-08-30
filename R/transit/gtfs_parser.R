# Polaris Public Transit: GTFS Timetable Parser & Calendar Schedule Engine
# High-speed streaming parser for General Transit Feed Specification feeds

#' Convert HH:MM:SS String to Seconds Past Midnight
#'
#' Handles GTFS overnight operating schedules where hours can exceed 24 (e.g. 25:30:00).
#'
#' @param time_str Character string in 'HH:MM:SS' format
#' @return Integer seconds past midnight
#' @export
gtfs_time_to_seconds <- function(time_str) {
  if (is.na(time_str) || !nzchar(trimws(time_str))) return(NA_integer_)
  parts <- as.integer(strsplit(trimws(time_str), ":")[[1]])
  if (length(parts) != 3L) return(NA_integer_)
  as.integer(parts[1] * 3600L + parts[2] * 60L + parts[3])
}

#' Convert Seconds Past Midnight to HH:MM:SS String
#' @export
seconds_to_gtfs_time <- function(seconds) {
  if (is.na(seconds)) return("")
  sec <- as.integer(seconds)
  hrs <- sec %/% 3600L
  rem <- sec %% 3600L
  mins <- rem %/% 60L
  secs <- rem %% 60L
  sprintf("%02d:%02d:%02d", hrs, mins, secs)
}

#' Parse GTFS Feed Directory
#'
#' Ingests raw CSV/text files from a standard GTFS feed directory:
#' stops.txt, routes.txt, trips.txt, stop_times.txt, calendar.txt, transfers.txt.
#'
#' @param gtfs_dir Directory path containing GTFS text files
#' @return S3 object of class polaris_gtfs_feed
#' @export
parse_gtfs_feed <- function(gtfs_dir) {
  read_gtfs_file <- function(filename, required = TRUE) {
    p <- file.path(gtfs_dir, filename)
    if (!file.exists(p)) {
      if (required) stop(sprintf("parse_gtfs_feed: required file '%s' not found", filename))
      return(data.frame())
    }
    # Read CSV with comma separator
    utils::read.csv(p, stringsAsFactors = FALSE, colClasses = "character")
  }

  stops_df <- read_gtfs_file("stops.txt", required = TRUE)
  routes_df <- read_gtfs_file("routes.txt", required = TRUE)
  trips_df <- read_gtfs_file("trips.txt", required = TRUE)
  stop_times_df <- read_gtfs_file("stop_times.txt", required = TRUE)
  calendar_df <- read_gtfs_file("calendar.txt", required = FALSE)
  transfers_df <- read_gtfs_file("transfers.txt", required = FALSE)

  # Validate mandatory columns
  stop_cols <- c("stop_id", "stop_name", "stop_lat", "stop_lon")
  for (sc in stop_cols) {
    if (!(sc %in% names(stops_df))) {
      stop(sprintf("parse_gtfs_feed: stops.txt missing required column '%s'", sc))
    }
  }

  # Parse numeric stop coordinates
  stops_clean <- data.frame(
    stop_id = as.character(stops_df$stop_id),
    stop_name = as.character(stops_df$stop_name),
    lat = as.numeric(stops_df$stop_lat),
    lon = as.numeric(stops_df$stop_lon),
    stringsAsFactors = FALSE
  )

  # Parse stop_times departure and arrival seconds
  st_clean <- data.frame(
    trip_id = as.character(stop_times_df$trip_id),
    arrival_time = vapply(stop_times_df$arrival_time, gtfs_time_to_seconds, integer(1)),
    departure_time = vapply(stop_times_df$departure_time, gtfs_time_to_seconds, integer(1)),
    stop_id = as.character(stop_times_df$stop_id),
    stop_sequence = as.integer(stop_times_df$stop_sequence),
    stringsAsFactors = FALSE
  )

  # Sort stop_times by trip_id and stop_sequence
  st_clean <- st_clean[order(st_clean$trip_id, st_clean$stop_sequence), ]

  feed <- list(
    stops = stops_clean,
    routes = routes_df,
    trips = trips_df,
    stop_times = st_clean,
    calendar = calendar_df,
    transfers = transfers_df
  )

  structure(feed, class = "polaris_gtfs_feed")
}

#' Create Synthetic In-Memory GTFS Feed
#'
#' Helper for testing and isolated simulation environments without requiring external files.
#'
#' @export
create_synthetic_gtfs <- function(stops_df, routes_df, trips_df, stop_times_df, transfers_df = NULL) {
  feed <- list(
    stops = stops_df,
    routes = routes_df,
    trips = trips_df,
    stop_times = stop_times_df,
    calendar = data.frame(),
    transfers = if (!is.null(transfers_df)) transfers_df else data.frame()
  )
  structure(feed, class = "polaris_gtfs_feed")
}
