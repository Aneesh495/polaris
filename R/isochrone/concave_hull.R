# Polaris Isochrone: Concave Hull Boundary Extraction
# Computes non-convex boundary contours from reachable point clouds via k-NN walk

#' Extract Concave Hull Polygon from 2D Coordinates
#'
#' Traces the boundary of a spatial point cloud using an adaptive k-nearest
#' neighbor angular deviation walk (Moreira & Santos concave hull algorithm).
#'
#' @param points Data frame or matrix with lat and lon columns
#' @param k Initial nearest neighbors count (default 5, must be >= 3)
#' @return Data frame with lat and lon columns defining the closed boundary polygon
#' @export
concave_hull <- function(points, k = 5L) {
  if (is.data.frame(points)) {
    pts <- cbind(as.numeric(points$lat), as.numeric(points$lon))
  } else if (is.matrix(points)) {
    pts <- points
  } else {
    stop("concave_hull: points must be a matrix or data.frame with lat, lon")
  }

  n <- nrow(pts)
  if (n <= 3L) {
    if (n < 3L) return(data.frame(lat = pts[, 1], lon = pts[, 2]))
    # Return closed triangle
    return(data.frame(
      lat = c(pts[, 1], pts[1, 1]),
      lon = c(pts[, 2], pts[1, 2])
    ))
  }

  k <- as.integer(max(3L, min(n - 1L, k)))

  # Helper: 2D Euclidean distance squared on local patch
  dist_sq <- function(p1, p2) {
    (p1[1] - p2[1])^2 + (p1[2] - p2[2])^2
  }

  # Helper: normalized turn angle relative to previous direction vector
  # Returns angle in [0, 2*pi) measured clockwise
  turn_angle <- function(prev_p, curr_p, cand_p) {
    v_prev <- c(curr_p[1] - prev_p[1], curr_p[2] - prev_p[2])
    v_cand <- c(cand_p[1] - curr_p[1], cand_p[2] - curr_p[2])

    ang_prev <- atan2(v_prev[2], v_prev[1])
    ang_cand <- atan2(v_cand[2], v_cand[1])

    diff <- ang_prev - ang_cand
    (diff + 2.0 * pi) %% (2.0 * pi)
  }

  # Find lowest latitude point as guaranteed boundary starting seed
  min_lat_idx <- which.min(pts[, 1])
  first_point <- pts[min_lat_idx, ]

  hull_indices <- integer(n + 1L)
  hull_indices[1L] <- min_lat_idx
  hull_len <- 1L

  curr_idx <- min_lat_idx
  prev_point <- c(first_point[1], first_point[2] - 1.0) # Horizontal reference

  visited <- logical(n)
  visited[min_lat_idx] <- TRUE

  max_steps <- 2L * n
  step <- 0L

  while (step < max_steps) {
    step <- step + 1L
    curr_point <- pts[curr_idx, ]

    # Find k nearest neighbors
    dists <- vapply(seq_len(n), function(i) {
      if (i == curr_idx) Inf else dist_sq(curr_point, pts[i, ])
    }, numeric(1))

    # Allow returning to first point if hull has at least 3 vertices
    cand_indices <- order(dists)[seq_len(min(k, n - 1L))]
    cand_indices <- cand_indices[!visited[cand_indices] | (cand_indices == min_lat_idx & hull_len >= 3L)]

    if (length(cand_indices) == 0L) {
      # No unvisited neighbor in k: increase k adaptively
      k <- min(n - 1L, k + 2L)
      cand_indices <- order(dists)[seq_len(k)]
      cand_indices <- cand_indices[!visited[cand_indices] | (cand_indices == min_lat_idx & hull_len >= 3L)]
      if (length(cand_indices) == 0L) break
    }

    # Pick candidate with maximum clockwise turn angle (rightmost deviation)
    angles <- vapply(cand_indices, function(idx) {
      turn_angle(prev_point, curr_point, pts[idx, ])
    }, numeric(1))

    best_cand_idx <- cand_indices[which.max(angles)]

    if (best_cand_idx == min_lat_idx && hull_len >= 3L) {
      # Polygon closed successfully!
      hull_len <- hull_len + 1L
      hull_indices[hull_len] <- min_lat_idx
      break
    }

    prev_point <- curr_point
    curr_idx <- best_cand_idx
    visited[curr_idx] <- TRUE
    hull_len <- hull_len + 1L
    hull_indices[hull_len] <- curr_idx
  }

  if (hull_indices[hull_len] != min_lat_idx) {
    # Close polygon explicitly if not closed
    hull_len <- hull_len + 1L
    hull_indices[hull_len] <- min_lat_idx
  }

  final_indices <- hull_indices[seq_len(hull_len)]
  data.frame(
    lat = pts[final_indices, 1],
    lon = pts[final_indices, 2]
  )
}
