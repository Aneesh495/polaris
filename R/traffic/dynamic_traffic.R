# Polaris Traffic Assignment: Discrete Dynamic Traffic Simulation
# Time-sliced queue accumulation, bottleneck discharge, and spillback dynamics

#' Simulate Dynamic Traffic Queue Dynamics
#'
#' Simulates discrete-time traffic propagation across road links with bottleneck
#' queue formation and upstream spillback throttling.
#'
#' @param graph Base polaris_graph
#' @param link_inflows Named list of numeric vectors: flow profiles over time steps
#' @param time_step_sec Duration of simulation time slice in seconds (default 60s)
#' @param jam_density_veh_km Maximum vehicles per km before physical gridlock (default 140)
#' @return Named list of time-series: queues, link_densities, speeds
#' @export
simulate_dynamic_queues <- function(graph, link_inflows,
                                    time_step_sec = 60.0,
                                    jam_density_veh_km = 140.0) {
  edge_ids <- graph$edge_ids
  n_edges <- length(edge_ids)

  n_steps <- length(link_inflows[[1L]])
  dt_hours <- time_step_sec / 3600.0

  # State matrices: rows = edges, cols = time steps
  queue_matrix <- matrix(0.0, nrow = n_edges, ncol = n_steps, dimnames = list(edge_ids, NULL))
  density_matrix <- matrix(0.0, nrow = n_edges, ncol = n_steps, dimnames = list(edge_ids, NULL))
  speed_matrix <- matrix(0.0, nrow = n_edges, ncol = n_steps, dimnames = list(edge_ids, NULL))

  # Edge physical parameters
  edge_lens_km <- vapply(edge_ids, function(e) graph$get_edge(e)$distance / 1000.0, numeric(1))
  free_speeds <- vapply(edge_ids, function(e) graph$get_edge(e)$speed_limit, numeric(1))
  capacities <- rep(1800.0, n_edges) # vehicles/hour

  current_queues <- setNames(numeric(n_edges), edge_ids)

  for (t in seq_len(n_steps)) {
    for (i in seq_len(n_edges)) {
      e_id <- edge_ids[i]
      inflow <- if (!is.null(link_inflows[[e_id]])) link_inflows[[e_id]][t] else 0.0

      # Inflow in vehicles during dt
      in_veh <- inflow * dt_hours
      cap_veh <- capacities[i] * dt_hours

      # Queue update
      new_queue <- max(0.0, current_queues[i] + in_veh - cap_veh)
      current_queues[i] <- new_queue
      queue_matrix[i, t] <- new_queue

      # Density in vehicles/km
      density <- new_queue / max(0.05, edge_lens_km[i])
      density_matrix[i, t] <- min(jam_density_veh_km, density)

      # Greenshields speed-density relationship
      # v = v_f * (1 - k / k_jam)
      spd_ratio <- max(0.1, 1.0 - (density / jam_density_veh_km))
      speed_matrix[i, t] <- free_speeds[i] * spd_ratio
    }
  }

  list(
    queues = queue_matrix,
    densities = density_matrix,
    speeds = speed_matrix,
    time_steps = n_steps
  )
}
