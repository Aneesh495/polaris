# Polaris Core Spatial Index: 2D Spatial R-Tree with Quadratic Split
# Provides O(log N) bounding-box intersection queries and branch-and-bound k-NN search

#' Compute Area of a Bounding Box
#' @export
bbox_area <- function(bbox) {
  dlat <- max(0.0, bbox$max_lat - bbox$min_lat)
  dlon <- max(0.0, bbox$max_lon - bbox$min_lon)
  dlat * dlon
}

#' Check if Two Bounding Boxes Intersect
#' @export
bbox_intersects <- function(b1, b2) {
  !(b1$max_lat < b2$min_lat || b1$min_lat > b2$max_lat ||
    b1$max_lon < b2$min_lon || b1$min_lon > b2$max_lon)
}

#' Combine Two Bounding Boxes into Enclosing Box
#' @export
bbox_combine <- function(b1, b2) {
  polaris_bbox(
    min_lat = min(b1$min_lat, b2$min_lat),
    min_lon = min(b1$min_lon, b2$min_lon),
    max_lat = max(b1$max_lat, b2$max_lat),
    max_lon = max(b1$max_lon, b2$max_lon)
  )
}

#' Minimum Distance from Point to Bounding Box
#'
#' Lower bound on distance (in degrees Euclidean or Haversine approximation)
#' for branch-and-bound k-NN pruning.
#' @export
bbox_point_distance <- function(bbox, lat, lon) {
  # Clamped nearest coordinate in box
  clamped_lat <- min(bbox$max_lat, max(bbox$min_lat, lat))
  clamped_lon <- min(bbox$max_lon, max(bbox$min_lon, lon))
  haversine_distance(lat, lon, clamped_lat, clamped_lon)
}

#' Spatial R-Tree Entry
#' @export
rtree_entry <- function(bbox, id, data = NULL, child = NULL) {
  list(bbox = bbox, id = as.character(id), data = data, child = child)
}

#' Spatial R-Tree Node
#' @export
rtree_node <- function(is_leaf = TRUE) {
  node <- new.env(parent = emptyenv())
  node$is_leaf <- as.logical(is_leaf)
  node$entries <- list()
  node$bbox <- NULL
  node
}

#' Recompute Bounding Box of an R-Tree Node
rtree_node_update_bbox <- function(node) {
  if (length(node$entries) == 0L) {
    node$bbox <- NULL
    return(NULL)
  }
  b <- node$entries[[1]]$bbox
  if (length(node$entries) > 1L) {
    for (i in 2:length(node$entries)) {
      b <- bbox_combine(b, node$entries[[i]]$bbox)
    }
  }
  node$bbox <- b
  b
}

#' Quadratic Split for R-Tree Node
rtree_split_node <- function(node, max_entries, min_entries) {
  entries <- node$entries
  n <- length(entries)

  # Step 1: Pick Seeds maximizing dead area
  max_dead_area <- -1.0
  seed1 <- 1L
  seed2 <- 2L

  for (i in seq_len(n - 1)) {
    for (j in seq(i + 1, n)) {
      comb <- bbox_combine(entries[[i]]$bbox, entries[[j]]$bbox)
      dead_area <- bbox_area(comb) - bbox_area(entries[[i]]$bbox) - bbox_area(entries[[j]]$bbox)
      if (dead_area > max_dead_area) {
        max_dead_area <- dead_area
        seed1 <- i
        seed2 <- j
      }
    }
  }

  group1 <- rtree_node(is_leaf = node$is_leaf)
  group2 <- rtree_node(is_leaf = node$is_leaf)

  group1$entries[[1]] <- entries[[seed1]]
  group2$entries[[1]] <- entries[[seed2]]
  rtree_node_update_bbox(group1)
  rtree_node_update_bbox(group2)

  remaining <- setdiff(seq_len(n), c(seed1, seed2))

  # Step 2: Distribute remaining entries
  for (idx in remaining) {
    entry <- entries[[idx]]
    # Check if either group needs all remaining entries to satisfy min_entries
    rem_count <- length(remaining) - which(remaining == idx) + 1L
    if (length(group1$entries) + rem_count == min_entries) {
      group1$entries[[length(group1$entries) + 1L]] <- entry
      rtree_node_update_bbox(group1)
      next
    }
    if (length(group2$entries) + rem_count == min_entries) {
      group2$entries[[length(group2$entries) + 1L]] <- entry
      rtree_node_update_bbox(group2)
      next
    }

    # Area expansion test
    comb1 <- bbox_combine(group1$bbox, entry$bbox)
    comb2 <- bbox_combine(group2$bbox, entry$bbox)
    exp1 <- bbox_area(comb1) - bbox_area(group1$bbox)
    exp2 <- bbox_area(comb2) - bbox_area(group2$bbox)

    if (exp1 < exp2) {
      group1$entries[[length(group1$entries) + 1L]] <- entry
      group1$bbox <- comb1
    } else if (exp2 < exp1) {
      group2$entries[[length(group2$entries) + 1L]] <- entry
      group2$bbox <- comb2
    } else {
      # Tie-break by smaller total area
      if (bbox_area(group1$bbox) <= bbox_area(group2$bbox)) {
        group1$entries[[length(group1$entries) + 1L]] <- entry
        group1$bbox <- comb1
      } else {
        group2$entries[[length(group2$entries) + 1L]] <- entry
        group2$bbox <- comb2
      }
    }
  }

  list(group1 = group1, group2 = group2)
}

#' Spatial R-Tree Structure
#'
#' @param max_entries Maximum entries per node before split (default 8)
#' @param min_entries Minimum entries per node (default 4)
#' @return An S3 object of class polaris_rtree
#' @export
polaris_rtree <- function(max_entries = 8L, min_entries = 4L) {
  tree <- new.env(parent = emptyenv())
  tree$max_entries <- as.integer(max_entries)
  tree$min_entries <- as.integer(min_entries)
  tree$root <- rtree_node(is_leaf = TRUE)
  tree$count <- 0L

  # Insert recursive
  insert_recursive <- function(node, entry) {
    if (node$is_leaf) {
      node$entries[[length(node$entries) + 1L]] <- entry
      rtree_node_update_bbox(node)
      if (length(node$entries) > tree$max_entries) {
        return(rtree_split_node(node, tree$max_entries, tree$min_entries))
      }
      return(NULL)
    }

    # Choose subtree with least area enlargement
    best_idx <- 1L
    min_exp <- Inf
    for (i in seq_along(node$entries)) {
      comb <- bbox_combine(node$entries[[i]]$bbox, entry$bbox)
      exp_area <- bbox_area(comb) - bbox_area(node$entries[[i]]$bbox)
      if (exp_area < min_exp) {
        min_exp <- exp_area
        best_idx <- i
      }
    }

    split_result <- insert_recursive(node$entries[[best_idx]]$child, entry)
    rtree_node_update_bbox(node)

    if (!is.null(split_result)) {
      # Replace original entry with group1 and append group2
      node$entries[[best_idx]] <- rtree_entry(
        bbox = split_result$group1$bbox,
        id = paste0("node_", best_idx),
        child = split_result$group1
      )
      node$entries[[length(node$entries) + 1L]] <- rtree_entry(
        bbox = split_result$group2$bbox,
        id = paste0("node_split_", length(node$entries) + 1L),
        child = split_result$group2
      )
      rtree_node_update_bbox(node)

      if (length(node$entries) > tree$max_entries) {
        return(rtree_split_node(node, tree$max_entries, tree$min_entries))
      }
    }
    NULL
  }

  tree$insert <- function(id, bbox, data = NULL) {
    entry <- rtree_entry(bbox = bbox, id = id, data = data)
    split_root <- insert_recursive(tree$root, entry)
    tree$count <- tree$count + 1L

    if (!is.null(split_root)) {
      new_root <- rtree_node(is_leaf = FALSE)
      new_root$entries[[1]] <- rtree_entry(
        bbox = split_root$group1$bbox,
        id = "root_child_1",
        child = split_root$group1
      )
      new_root$entries[[2]] <- rtree_entry(
        bbox = split_root$group2$bbox,
        id = "root_child_2",
        child = split_root$group2
      )
      rtree_node_update_bbox(new_root)
      tree$root <- new_root
    }
    invisible(NULL)
  }

  # Search box intersection
  search_recursive <- function(node, query_bbox, results) {
    if (is.null(node$bbox) || !bbox_intersects(node$bbox, query_bbox)) {
      return(results)
    }
    for (entry in node$entries) {
      if (bbox_intersects(entry$bbox, query_bbox)) {
        if (node$is_leaf) {
          results[[length(results) + 1L]] <- list(id = entry$id, data = entry$data, bbox = entry$bbox)
        } else {
          results <- search_recursive(entry$child, query_bbox, results)
        }
      }
    }
    results
  }

  tree$search <- function(query_bbox) {
    search_recursive(tree$root, query_bbox, list())
  }

  # Branch-and-bound k-NN search
  tree$knn <- function(lat, lon, k = 1L) {
    if (tree$count == 0L || k <= 0L) return(list())
    k <- min(as.integer(k), tree$count)

    pq <- polaris_indexed_pq(initial_capacity = 64L)
    # Store candidates in sorted list
    candidates <- list()

    # Search queue with lower bound distance
    queue <- list(list(dist = 0.0, node = tree$root))

    while (length(queue) > 0L) {
      # Pop element with minimum distance lower bound
      dists <- vapply(queue, function(x) x$dist, numeric(1))
      min_idx <- which.min(dists)
      curr <- queue[[min_idx]]
      queue <- queue[-min_idx]

      if (length(candidates) >= k && curr$dist > candidates[[k]]$distance) {
        # Pruning bound satisfied: all remaining boxes are further than the k-th best candidate
        break
      }

      if (curr$node$is_leaf) {
        for (entry in curr$node$entries) {
          # Calculate exact or representative distance
          d <- bbox_point_distance(entry$bbox, lat, lon)
          candidates[[length(candidates) + 1L]] <- list(
            id = entry$id,
            data = entry$data,
            bbox = entry$bbox,
            distance = d
          )
        }
        # Sort candidates ascending
        if (length(candidates) > 1L) {
          ord <- order(vapply(candidates, function(c) c$distance, numeric(1)))
          candidates <- candidates[ord]
        }
      } else {
        for (entry in curr$node$entries) {
          d_box <- bbox_point_distance(entry$bbox, lat, lon)
          queue[[length(queue) + 1L]] <- list(dist = d_box, node = entry$child)
        }
      }
    }

    if (length(candidates) > k) {
      candidates <- candidates[seq_len(k)]
    }
    candidates
  }

  structure(tree, class = "polaris_rtree")
}
