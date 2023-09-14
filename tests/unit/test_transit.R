# Unit Tests: GTFS Timetable Parsing, Pattern Indexing, and RAPTOR Query

# Test 1: Time Conversion Routines
assert_equal(gtfs_time_to_seconds("08:00:00"), 28800L, "08:00:00 must equal 28800 seconds")
assert_equal(gtfs_time_to_seconds("25:30:00"), 91800L, "25:30:00 must equal 91800 seconds (overnight)")
assert_equal(seconds_to_gtfs_time(28800L), "08:00:00", "28800 seconds converts to 08:00:00")

# Test 2: In-Memory Synthetic Timetable Feed
stops_df <- data.frame(
  stop_id = c("S_A", "S_B", "S_C", "S_D"),
  stop_name = c("Alpha Station", "Bravo Center", "Charlie Transit", "Delta Park"),
  stop_lat = c(37.75, 37.76, 37.77, 37.78),
  stop_lon = c(-122.45, -122.44, -122.43, -122.42),
  stringsAsFactors = FALSE
)

routes_df <- data.frame(
  route_id = c("R_LOCAL", "R_EXPRESS", "R_CONNECT"),
  route_short_name = c("1", "X", "3"),
  stringsAsFactors = FALSE
)

trips_df <- data.frame(
  route_id = c("R_LOCAL", "R_EXPRESS", "R_CONNECT"),
  trip_id = c("T_LOC_1", "T_EXP_1", "T_CON_1"),
  service_id = c("DAILY", "DAILY", "DAILY"),
  stringsAsFactors = FALSE
)

stop_times_df <- data.frame(
  trip_id = c("T_LOC_1", "T_LOC_1", "T_LOC_1",
              "T_EXP_1", "T_EXP_1",
              "T_CON_1", "T_CON_1"),
  arrival_time = c("08:00:00", "08:15:00", "08:35:00",
                   "08:05:00", "08:20:00",
                   "08:25:00", "08:45:00"),
  departure_time = c("08:00:00", "08:16:00", "08:35:00",
                     "08:05:00", "08:20:00",
                     "08:26:00", "08:45:00"),
  stop_id = c("S_A", "S_B", "S_C",
              "S_A", "S_C",
              "S_C", "S_D"),
  stop_sequence = c(1L, 2L, 3L,
                    1L, 2L,
                    1L, 2L),
  stringsAsFactors = FALSE
)

feed <- create_synthetic_gtfs(stops_df, routes_df, trips_df, stop_times_df)
raptor_net <- build_raptor_network(feed, max_transfer_walk_meters = 200.0)

assert_equal(length(raptor_net$stop_ids), 4L, "Network contains 4 stops")
assert_equal(length(raptor_net$patterns), 3L, "Network contains 3 route patterns")

# Test 3: RAPTOR Single-Leg Direct Query (S_A to S_C)
# Departs S_A at 08:00:00 (28800s).
# Local bus arrives S_C at 08:35 (30900s).
# Express bus departs S_A at 08:05 and arrives S_C at 08:20 (30000s) -> earlier!
res_ac <- polaris_raptor(raptor_net, "S_A", "S_C", departure_time_sec = 28800L, max_rounds = 2L)
assert_true(length(res_ac) >= 1L, "Must find at least 1 itinerary from A to C")
best_ac <- res_ac[[1L]]
assert_equal(best_ac$arrival_time, "08:20:00", "Express bus provides earlier arrival at 08:20:00")
assert_equal(best_ac$transfers, 0L, "Direct bus requires 0 transfers")

# Test 4: RAPTOR Multi-Leg Transfer Query (S_A to S_D)
# Express bus arrives S_C at 08:20.
# Connecting bus departs S_C at 08:26 and arrives S_D at 08:45.
res_ad <- polaris_raptor(raptor_net, "S_A", "S_D", departure_time_sec = 28800L, max_rounds = 3L)
assert_true(length(res_ad) >= 1L, "Must find connecting itinerary from A to D")
best_ad <- res_ad[[1L]]
assert_equal(best_ad$arrival_time, "08:45:00", "Connecting journey arrives at 08:45:00")
assert_equal(best_ad$transfers, 1L, "Connecting journey requires exactly 1 transfer")

# Test 5: Range-RAPTOR Window Query
range_res <- polaris_range_raptor(
  raptor_net = raptor_net,
  origin_stop_id = "S_A",
  target_stop_id = "S_D",
  start_time_sec = 28500L, # 07:55:00
  end_time_sec = 29400L,   # 08:10:00
  step_minutes = 5L
)
assert_true(length(range_res) >= 1L, "Range RAPTOR returns valid profile")
