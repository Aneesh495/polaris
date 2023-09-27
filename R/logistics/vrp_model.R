# Polaris Logistics: Vehicle Routing Problem (VRP) Data Models
# Problem definitions for Capacitated VRP and VRP with Time Windows (VRPTW)

#' VRP Customer Delivery Location
#'
#' @param id Unique customer identifier
#' @param lat Latitude in degrees
#' @param lon Longitude in degrees
#' @param demand Parcel capacity units demanded (e.g. packages, kg)
#' @param ready_time Earliest allowable delivery time in seconds (default 0)
#' @param due_time Latest allowable delivery time in seconds (default 86400)
#' @param service_time Dwell / unloading duration in seconds (default 300s = 5 mins)
#' @export
polaris_vrp_customer <- function(id, lat, lon, demand = 1.0,
                                ready_time = 0.0, due_time = 86400.0,
                                service_time = 300.0) {
  structure(
    list(
      id = as.character(id),
      coord = polaris_coordinate(lat, lon),
      demand = as.numeric(demand),
      ready_time = as.numeric(ready_time),
      due_time = as.numeric(due_time),
      service_time = as.numeric(service_time)
    ),
    class = "polaris_vrp_customer"
  )
}

#' VRP Central Distribution Depot
#'
#' @param id Depot identifier
#' @param lat Latitude in degrees
#' @param lon Longitude in degrees
#' @param ready_time Facility opening time in seconds (default 0)
#' @param due_time Facility closing time in seconds (default 86400)
#' @export
polaris_vrp_depot <- function(id, lat, lon, ready_time = 0.0, due_time = 86400.0) {
  structure(
    list(
      id = as.character(id),
      coord = polaris_coordinate(lat, lon),
      ready_time = as.numeric(ready_time),
      due_time = as.numeric(due_time)
    ),
    class = "polaris_vrp_depot"
  )
}

#' VRP Fleet Vehicle
#'
#' @param id Unique vehicle identifier
#' @param capacity Maximum load capacity units (default 100.0)
#' @param max_travel_time Maximum allowable route duration in seconds (default 28800 = 8h)
#' @param speed_mps Nominal transit speed in m/s (default 11.1 m/s ~ 40 km/h)
#' @export
polaris_vrp_vehicle <- function(id, capacity = 100.0,
                                max_travel_time = 28800.0,
                                speed_mps = 11.1) {
  structure(
    list(
      id = as.character(id),
      capacity = as.numeric(capacity),
      max_travel_time = as.numeric(max_travel_time),
      speed_mps = as.numeric(speed_mps)
    ),
    class = "polaris_vrp_vehicle"
  )
}

#' Complete VRP Problem Specification
#'
#' Encapsulates depot, customer delivery registry, fleet profile, and distance matrix.
#'
#' @param depot polaris_vrp_depot object
#' @param customers List of polaris_vrp_customer objects
#' @param vehicle_capacity Capacity per vehicle
#' @param num_vehicles Available fleet count
#' @param distance_matrix Optional precomputed symmetric/asymmetric distance matrix
#' @export
polaris_vrp_problem <- function(depot, customers,
                                vehicle_capacity = 100.0,
                                num_vehicles = 5L,
                                distance_matrix = NULL) {
  cust_ids <- vapply(customers, function(c) c$id, character(1))
  all_ids <- c(depot$id, cust_ids)
  n_all <- length(all_ids)

  # Compute distance matrix if not provided
  if (is.null(distance_matrix)) {
    coords <- vector("list", n_all)
    coords[[1L]] <- depot$coord
    for (i in seq_along(customers)) {
      coords[[i + 1L]] <- customers[[i]]$coord
    }
    d_mat <- matrix(0.0, nrow = n_all, ncol = n_all, dimnames = list(all_ids, all_ids))
    for (i in seq_len(n_all)) {
      for (j in seq_len(n_all)) {
        if (i != j) {
          d_mat[i, j] <- haversine_distance(
            coords[[i]]$lat, coords[[i]]$lon,
            coords[[j]]$lat, coords[[j]]$lon
          )
        }
      }
    }
    distance_matrix <- d_mat
  }

  prob <- list(
    depot = depot,
    customers = customers,
    customer_ids = cust_ids,
    all_ids = all_ids,
    vehicle_capacity = as.numeric(vehicle_capacity),
    num_vehicles = as.integer(num_vehicles),
    distance_matrix = distance_matrix
  )

  structure(prob, class = "polaris_vrp_problem")
}
