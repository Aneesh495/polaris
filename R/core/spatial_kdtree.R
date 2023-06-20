# Polaris Core Spatial KD-Tree: 2D/3D Point and Segment Spatial Partitioning
# High-throughput nearest-neighbor and radius range queries for GPS projection

#' Internal KD-Tree Node
kdtree_node <- function(point, id, axis, left = NULL, right = NULL, data = NULL) {
  list(
    point = point,   # numeric vector c(lat, lon) or c(x, y, z)
    id = as.character(id),
    axis = as.integer(axis),
    left = left,
    right = right,
    data = data
  )
}

#' Build Balanced 2D KD-Tree
#'
#' Recursively constructs a balanced KD-Tree using median splitting along alternating axes.
#'
#' @param points Matrix or data.frame with lat and lon columns
#' @param ids Character vector of identifiers
#' @param data List of arbitrary metadata payloads
#' @return Root node of the KD-Tree
#' @export
polaris_kdtree <- function(points, ids = NULL, data = NULL) {
  if (is.data.frame(points)) {
    pts <- cbind(as.numeric(points$lat), as.numeric(points$lon))
  } else if (is.matrix(points)) {
    pts <- points
  } else {
    stop("polaris_kdtree: points must be a numeric matrix or data.frame with lat, lon")
  }

  n <- nrow(pts)
  if (n == 0L) {
    tree <- new.env(parent = emptyenv())
    tree$root <- NULL
    tree$n <- 0L
    tree$dim <- 2L
    return(structure(tree, class = "polaris_kdtree"))
  }

  dim <- ncol(pts)
  if (is.null(ids)) {
    ids <- as.character(seq_len(n))
  }
  if (is.null(data)) {
    data <- vector("list", n)
  }

  build_tree <- function(indices, depth) {
    if (length(indices) == 0L) return(NULL)

    axis <- (depth %% dim) + 1L

    # Sort indices by coordinate along current axis
    vals <- pts[indices, axis]
    ord <- order(vals)
    sorted_idx <- indices[ord]

    median_pos <- as.integer((length(sorted_idx) + 1L) %/% 2L)
    median_idx <- sorted_idx[median_pos]

    left_idx <- if (median_pos > 1L) sorted_idx[seq_len(median_pos - 1L)] else integer(0)
    right_idx <- if (median_pos < length(sorted_idx)) sorted_idx[seq(median_pos + 1L, length(sorted_idx))] else integer(0)

    kdtree_node(
      point = pts[median_idx, ],
      id = ids[median_idx],
      axis = axis,
      left = build_tree(left_idx, depth + 1L),
      right = build_tree(right_idx, depth + 1L),
      data = data[[median_idx]]
    )
  }

  tree <- new.env(parent = emptyenv())
  tree$root <- build_tree(seq_len(n), depth = 0L)
  tree$n <- n
  tree$dim <- dim

  # Query nearest neighbor using Euclidean or Haversine metric
  tree$nearest <- function(query_lat, query_lon) {
    if (is.null(tree$root)) return(NULL)
    best <- list(dist = Inf, node = NULL)

    search_nearest <- function(node) {
      if (is.null(node)) return()

      # Distance to current node in meters
      d <- haversine_distance(query_lat, query_lon, node$point[1], node$point[2])
      if (d < best$dist) {
        best$dist <<- d
        best$node <<- node
      }

      axis <- node$axis
      q_val <- if (axis == 1L) query_lat else query_lon
      node_val <- node$point[axis]

      # Determine primary and secondary branches
      if (q_val < node_val) {
        first <- node$left
        second <- node$right
      } else {
        first <- node$right
        second <- node$left
      }

      search_nearest(first)

      # Check if hypersphere crosses splitting hyperplane
      # Approximate axis degree distance to meters:
      # 1 deg lat ~ 111,139m; 1 deg lon ~ 111,139m * cos(lat)
      axis_scale <- if (axis == 1L) 111139.0 else 111139.0 * cos(deg2rad(query_lat))
      plane_dist <- abs(q_val - node_val) * axis_scale

      if (plane_dist < best$dist) {
        search_nearest(second)
      }
    }

    search_nearest(tree$root)

    if (is.null(best$node)) return(NULL)
    list(
      id = best$node$id,
      lat = best$node$point[1],
      lon = best$node$point[2],
      distance_meters = best$dist,
      data = best$node$data
    )
  }

  # Radius search: find all points within radius_meters
  tree$radius_search <- function(query_lat, query_lon, radius_meters) {
    if (is.null(tree$root)) return(list())
    matches <- list()

    search_radius <- function(node) {
      if (is.null(node)) return()

      d <- haversine_distance(query_lat, query_lon, node$point[1], node$point[2])
      if (d <= radius_meters) {
        matches[[length(matches) + 1L]] <<- list(
          id = node$id,
          lat = node$point[1],
          lon = node$point[2],
          distance_meters = d,
          data = node$data
        )
      }

      axis <- node$axis
      q_val <- if (axis == 1L) query_lat else query_lon
      node_val <- node$point[axis]

      axis_scale <- if (axis == 1L) 111139.0 else 111139.0 * cos(deg2rad(query_lat))
      plane_dist <- abs(q_val - node_val) * axis_scale

      if (q_val < node_val) {
        search_radius(node$left)
        if (plane_dist <= radius_meters) {
          search_radius(node$right)
        }
      } else {
        search_radius(node$right)
        if (plane_dist <= radius_meters) {
          search_radius(node$left)
        }
      }
    }

    search_radius(tree$root)
    matches
  }

  structure(tree, class = "polaris_kdtree")
}
