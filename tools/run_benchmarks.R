#!/usr/bin/env Rscript
# Polaris Performance Benchmark Suite
# Benchmarks micro-computations and macro-subsystem query latency

args <- commandArgs(trailingOnly = TRUE)
out_file <- "artifacts/benchmarks.json"
for (i in seq_along(args)) {
  if (args[i] %in% c("-o", "--output") && (i + 1L) <= length(args)) {
    out_file <- args[i + 1L]
  }
}

dir.create(dirname(out_file), showWarnings = FALSE, recursive = TRUE)

root <- normalizePath(getwd())
source(file.path(root, "R", "polaris_loader.R"))
polaris_load_all(root)

cat("========================================================================\n")
cat("POLARIS HIGH-PERFORMANCE BENCHMARK SUITE\n")
cat(sprintf("Platform: %s %s (%s, %s)\n", Sys.info()["sysname"], Sys.info()["release"], Sys.info()["machine"], R.version.string))
cat("========================================================================\n\n")

benchmark_results <- list()

measure_time <- function(name, unit_label, fn, iterations = 100L) {
  # Warmup
  invisible(fn())
  
  gc(verbose = FALSE)
  t0 <- proc.time()
  for (i in seq_len(iterations)) {
    fn()
  }
  elapsed <- (proc.time() - t0)[["elapsed"]]
  avg_time_ms <- (elapsed / iterations) * 1000.0
  throughput <- if (elapsed > 0) iterations / elapsed else 1e7
  
  cat(sprintf("%-48s │ %8.3f ms/op │ %10.1f ops/sec (%s)\n",
              name, avg_time_ms, throughput, unit_label))
  
  list(
    name = name,
    unit = unit_label,
    iterations = iterations,
    total_time_sec = elapsed,
    latency_ms_per_op = avg_time_ms,
    throughput_ops_per_sec = throughput
  )
}

cat("--- MICRO-BENCHMARKS: GEODESY & SPATIAL INDEXING -----------------------\n")
lat1 <- 37.7749; lon1 <- -122.4194; lat2 <- 34.0522; lon2 <- -118.2437

benchmark_results[[1]] <- measure_time(
  "Haversine Great Circle Distance",
  "queries",
  function() haversine_distance(lat1, lon1, lat2, lon2),
  iterations = 10000L
)

benchmark_results[[2]] <- measure_time(
  "Vincenty Geodesic Inverse (WGS-84)",
  "queries",
  function() vincenty_inverse(lat1, lon1, lat2, lon2),
  iterations = 2000L
)

benchmark_results[[3]] <- measure_time(
  "Geohash Precision-7 Encoding",
  "encodes",
  function() geohash_encode(lat1, lon1, precision = 7L),
  iterations = 5000L
)

# Spatial Tree query benchmark
rtree <- polaris_rtree(max_entries = 8L)
for (i in 1:200) {
  b <- polaris_bbox(37.7 + runif(1)*0.05, -122.4 + runif(1)*0.05, 37.75 + runif(1)*0.05, -122.35 + runif(1)*0.05)
  rtree$insert(sprintf("item_%d", i), b)
}
qbox <- polaris_bbox(37.72, -122.38, 37.78, -122.32)

benchmark_results[[4]] <- measure_time(
  "R-Tree Bounding Box Intersection (200 items)",
  "queries",
  function() rtree$search(qbox),
  iterations = 1000L
)

cat("\n--- DATA STRUCTURES: MIN-HEAP & PRIORITY QUEUE -------------------------\n")
pq <- polaris_indexed_pq(initial_capacity = 1024L)
benchmark_results[[5]] <- measure_time(
  "Indexed Min-Heap Push & Pop Cycle (50 elements)",
  "cycles",
  function() {
    for (i in 1:50) pq$push(as.character(i), runif(1, 1, 1000))
    for (i in 1:50) pq$pop()
  },
  iterations = 50L
)

cat("\n--- MACRO-BENCHMARKS: GRAPH ROUTING ------------------------------------\n")
# Build a 10x10 synthetic grid network (100 vertices, ~360 directed edges)
grid_g <- polaris_graph()
for (r in 0:9) {
  for (c in 0:9) {
    vid <- sprintf("N_%d_%d", r, c)
    grid_g$add_node(vid, 37.70 + r*0.01, -122.45 + c*0.01)
  }
}
edge_cnt <- 1L
for (r in 0:9) {
  for (c in 0:9) {
    u <- sprintf("N_%d_%d", r, c)
    if (r < 9) {
      v <- sprintf("N_%d_%d", r + 1, c)
      grid_g$add_edge(sprintf("e%d", edge_cnt), u, v, distance = 1000.0, travel_time = 60.0)
      edge_cnt <- edge_cnt + 1L
      grid_g$add_edge(sprintf("e%d", edge_cnt), v, u, distance = 1000.0, travel_time = 60.0)
      edge_cnt <- edge_cnt + 1L
    }
    if (c < 9) {
      v <- sprintf("N_%d_%d", r, c + 1)
      grid_g$add_edge(sprintf("e%d", edge_cnt), u, v, distance = 1000.0, travel_time = 60.0)
      edge_cnt <- edge_cnt + 1L
      grid_g$add_edge(sprintf("e%d", edge_cnt), v, u, distance = 1000.0, travel_time = 60.0)
      edge_cnt <- edge_cnt + 1L
    }
  }
}
grid_g$build_csr()

benchmark_results[[6]] <- measure_time(
  "Unidirectional Dijkstra (10x10 Grid)",
  "routes",
  function() polaris_dijkstra(grid_g, "N_0_0", "N_9_9"),
  iterations = 50L
)

benchmark_results[[7]] <- measure_time(
  "Bidirectional Dijkstra (10x10 Grid)",
  "routes",
  function() polaris_bidirectional_dijkstra(grid_g, "N_0_0", "N_9_9"),
  iterations = 50L
)

benchmark_results[[8]] <- measure_time(
  "A* Search with Euclidean Heuristic",
  "routes",
  function() polaris_astar(grid_g, "N_0_0", "N_9_9"),
  iterations = 50L
)

# Benchmark Contraction Hierarchies Preprocessing and Querying
ch_bundle <- ch_preprocess(grid_g, metric = "distance")

benchmark_results[[9]] <- measure_time(
  "Contraction Hierarchies Query Solver",
  "queries",
  function() polaris_ch_route(ch_bundle, "N_0_0", "N_9_9"),
  iterations = 200L
)

cat("\n--- MACRO-BENCHMARKS: MAP MATCHING & VITERBI ---------------------------\n")
gps_trace_df <- data.frame(
  lat = 37.70 + (0:5)*0.01 + rnorm(6, 0, 0.0001),
  lon = -122.45 + (0:5)*0.01 + rnorm(6, 0, 0.0001),
  timestamp = as.numeric(as.POSIXct("2023-11-18 10:00:00", tz = "UTC")) + (0:5)*5
)

benchmark_results[[10]] <- measure_time(
  "HMM Viterbi Map Match (6 GPS Pings)",
  "trajectories",
  function() polaris_map_match(grid_g, gps_trace_df, search_radius_meters = 2500.0),
  iterations = 10L
)

cat("\n--- MACRO-BENCHMARKS: LOGISTICS & USER EQUILIBRIUM ---------------------\n")
# Clarke-Wright VRP
depot <- polaris_vrp_depot("DEP", 37.75, -122.40)
customers <- lapply(1:12, function(i) {
  polaris_vrp_customer(sprintf("C%d", i), 37.72 + runif(1)*0.06, -122.43 + runif(1)*0.06, demand = 10.0 + runif(1)*10.0)
})
vrp_prob <- polaris_vrp_problem(depot, customers, vehicle_capacity = 100.0)

benchmark_results[[11]] <- measure_time(
  "Clarke-Wright Savings VRP (12 Customers)",
  "solves",
  function() clarke_wright_savings(vrp_prob),
  iterations = 20L
)

# Frank-Wolfe Traffic Assignment (od_mat with vertex IDs, 3 iterations)
od_mat <- matrix(0.0, nrow = 2, ncol = 2,
                 dimnames = list(c("N_0_0", "N_1_1"), c("N_9_9", "N_8_8")))
od_mat["N_0_0", "N_9_9"] <- 100.0
od_mat["N_1_1", "N_8_8"] <- 80.0

benchmark_results[[12]] <- measure_time(
  "Frank-Wolfe Static User Equilibrium (3 iters)",
  "simulations",
  function() polaris_frank_wolfe(grid_g, od_mat, capacities = list(), max_iterations = 3L, target_relative_gap = 1e-4),
  iterations = 3L
)

cat("========================================================================\n")
cat(sprintf("Summary: 12 benchmark workloads completed successfully.\n"))

# Serialize benchmark artifact
json_entries <- vapply(benchmark_results, function(b) {
  sprintf(
    "    {\n      \"name\": \"%s\",\n      \"unit\": \"%s\",\n      \"iterations\": %d,\n      \"total_time_sec\": %.6f,\n      \"latency_ms_per_op\": %.4f,\n      \"throughput_ops_per_sec\": %.2f\n    }",
    b$name, b$unit, b$iterations, b$total_time_sec, b$latency_ms_per_op, b$throughput_ops_per_sec
  )
}, character(1))

bench_json <- sprintf(
  "{\n  \"timestamp\": \"%s\",\n  \"platform\": {\n    \"sysname\": \"%s\",\n    \"release\": \"%s\",\n    \"machine\": \"%s\",\n    \"r_version\": \"%s\"\n  },\n  \"benchmarks\": [\n%s\n  ]\n}",
  format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
  Sys.info()["sysname"], Sys.info()["release"], Sys.info()["machine"], R.version.string,
  paste(json_entries, collapse = ",\n")
)

writeLines(bench_json, con = out_file)
cat(sprintf("Exported benchmark telemetry to %s\n", out_file))
