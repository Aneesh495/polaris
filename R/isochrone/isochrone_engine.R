# Polaris Isochrone: Travel-Time Wavefront Propagation Engine
# Computes reachable vertex sets, forward/backward accessibility surfaces, and catchment radii

#' Compute Reachable Vertex Set from Origin
#'
#' Explores the road network up to a maximum travel time or distance budget,
#' capturing all accessible vertices and their minimal arrival costs.
#'
#' @param graph Base polaris_graph object
#' @param origin_id Origin node identifier
#' @param max_cost Maximum travel budget (seconds if metric='time', meters if metric='distance')
#' @param metric 'time' (seconds) or 'distance' (meters)
#' @param reverse Logical, if TRUE computes inward reachability toward destination
#' @return Data frame of reachable nodes: id, lat, lon, cost
#' @export
polaris_isochrone_wavefront <- function(graph, origin_id, max_cost = 900.0,
                                       metric = "time", reverse = FALSE) {
  if (!graph$csr_built) graph$build_csr()

  s_str <- as.character(origin_id)
  s_idx <- graph$node_to_idx[[s_str]]
  if (is.null(s_idx)) stop(sprintf("isochrone_wavefront: origin '%s' not found", s_str))

  n <- graph$node_count()
  use_time <- (metric == "time")

  dist_arr <- rep(Inf, n)
  settled <- logical(n)
  pq <- polaris_indexed_pq(initial_capacity = min(1024L, n))

  dist_arr[s_idx] <- 0.0
  pq$push(as.character(s_idx), 0.0)

  # Choose CSR arrays based on forward vs reverse direction
  offsets <- if (reverse) graph$bwd_offsets else graph$fwd_offsets
  targets <- if (reverse) graph$bwd_targets else graph$fwd_targets
  weights <- if (reverse) graph$bwd_weights else graph$fwd_weights
  times   <- if (reverse) graph$bwd_times   else graph$fwd_times

  while (!pq$is_empty()) {
    top <- pq$pop()
    u <- as.integer(top$element)
    u_cost <- top$priority

    if (u_cost > max_cost) break # Budget exhausted
    if (settled[u]) next
    settled[u] <- TRUE

    start_e <- offsets[u]
    end_e <- offsets[u + 1L] - 1L

    if (start_e <= end_e) {
      for (e_ptr in start_e:end_e) {
        v <- targets[e_ptr]
        if (settled[v]) next

        edge_c <- if (use_time) times[e_ptr] else weights[e_ptr]
        new_cost <- u_cost + edge_c

        if (new_cost <= max_cost && new_cost < dist_arr[v]) {
          dist_arr[v] <- new_cost
          pq$push(as.character(v), new_cost)
        }
      }
    }
  }

  reachable_indices <- which(settled)
  n_reach <- length(reachable_indices)

  if (n_reach == 0L) {
    return(data.frame(id = character(0), lat = numeric(0), lon = numeric(0), cost = numeric(0)))
  }

  out_ids <- graph$idx_to_node[reachable_indices]
  out_lats <- numeric(n_reach)
  out_lons <- numeric(n_reach)
  out_costs <- dist_arr[reachable_indices]

  for (i in seq_len(n_reach)) {
    c_obj <- graph$node_coords[[out_ids[i]]]
    out_lats[i] <- c_obj$lat
    out_lons[i] <- c_obj$lon
  }

  data.frame(
    id = out_ids,
    lat = out_lats,
    lon = out_lons,
    cost = out_costs,
    stringsAsFactors = FALSE
  )
}
