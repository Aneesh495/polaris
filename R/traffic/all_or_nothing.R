# Polaris Traffic Assignment: All-or-Nothing (AON) Shortest Path Loading
# Assigns entire OD trip demand to minimum-cost paths without capacity limits

#' All-or-Nothing Traffic Flow Assignment
#'
#' Evaluates shortest paths for all active OD demand pairs and routes 100% of demand
#' along the identified shortest links.
#'
#' @param graph Base polaris_graph with edge travel times updated
#' @param od_matrix Named numeric matrix of origin-destination trip demands
#' @return Named numeric vector of loaded link flows
#' @export
all_or_nothing_assignment <- function(graph, od_matrix) {
  if (!graph$csr_built) graph$build_csr()

  edge_ids <- graph$edge_ids
  flows <- setNames(numeric(length(edge_ids)), edge_ids)

  origins <- rownames(od_matrix)
  destinations <- colnames(od_matrix)

  for (o in origins) {
    # Check if origin has any non-zero demand
    demands_o <- od_matrix[o, ]
    active_dests <- names(demands_o)[demands_o > 0.0]
    if (length(active_dests) == 0L) next

    # Compute shortest path tree from origin
    tree <- polaris_dijkstra(graph, source_id = o, metric = "time")

    for (d in active_dests) {
      q_od <- demands_o[[d]]
      d_idx <- graph$node_to_idx[[d]]
      if (is.null(d_idx) || is.infinite(tree$travel_times[d_idx])) next

      # Backtrack path from destination to origin
      curr <- d_idx
      while (curr != 0L && curr != graph$node_to_idx[[o]]) {
        p_edge <- tree$parent_edges[curr]
        if (nzchar(p_edge)) {
          flows[[p_edge]] <- flows[[p_edge]] + q_od
        }
        curr <- tree$parent_nodes[curr]
      }
    }
  }

  flows
}
