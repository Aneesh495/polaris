# Polaris Routing Engine: Origin-Destination Distance & Travel-Time Matrix
# High-throughput N x M matrix computation using bucketed Dijkstra search trees

#' Compute N x M Distance and Duration Matrix
#'
#' Evaluates shortest path travel times or distances between multiple origin
#' and destination locations using one-to-many Dijkstra search tree expansion.
#'
#' @param graph Base polaris_graph object
#' @param origins Character vector of origin node identifiers
#' @param destinations Character vector of destination node identifiers
#' @param metric 'distance' (meters) or 'time' (seconds)
#' @return Named numeric matrix of dimension length(origins) x length(destinations)
#' @export
polaris_matrix <- function(graph, origins, destinations, metric = "distance") {
  if (!graph$csr_built) graph$build_csr()

  orig_ids <- as.character(origins)
  dest_ids <- as.character(destinations)

  n_orig <- length(orig_ids)
  n_dest <- length(dest_ids)

  res_mat <- matrix(Inf, nrow = n_orig, ncol = n_dest,
                    dimnames = list(orig_ids, dest_ids))

  dest_indices <- integer(n_dest)
  for (j in seq_len(n_dest)) {
    idx <- graph$node_to_idx[[dest_ids[j]]]
    dest_indices[j] <- if (!is.null(idx)) idx else 0L
  }

  use_time <- (metric == "time")

  for (i in seq_len(n_orig)) {
    s_str <- orig_ids[i]
    s_idx <- graph$node_to_idx[[s_str]]
    if (is.null(s_idx)) next

    # Run one-to-all Dijkstra
    tree <- polaris_dijkstra(graph, source_id = s_str, metric = metric)
    costs <- if (use_time) tree$travel_times else tree$distances

    for (j in seq_len(n_dest)) {
      d_idx <- dest_indices[j]
      if (d_idx > 0L) {
        res_mat[i, j] <- costs[d_idx]
      }
    }
  }

  res_mat
}

#' All-Pairs Distance and Duration Matrix
#'
#' Computes complete N x N shortest path matrix across all vertices.
#'
#' @param graph Base polaris_graph object
#' @param metric 'distance' or 'time'
#' @return Named numeric N x N matrix
#' @export
polaris_all_pairs <- function(graph, metric = "distance") {
  polaris_matrix(graph, origins = graph$node_ids, destinations = graph$node_ids, metric = metric)
}
