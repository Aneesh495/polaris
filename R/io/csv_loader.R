# Polaris IO: Streaming CSV Network Loader
# Ingests tabular CSV node, edge, and OD matrices into native Polaris graphs

#' Load Polaris Graph from CSV Files
#'
#' @param nodes_csv Path to nodes.csv (id, lat, lon, optional ele)
#' @param edges_csv Path to edges.csv (id, source, target, distance, optional speed_limit, oneway, highway_type)
#' @return polaris_graph object with built CSR
#' @export
load_graph_from_csv <- function(nodes_csv, edges_csv) {
  if (!file.exists(nodes_csv)) stop(sprintf("load_graph_from_csv: nodes file '%s' not found", nodes_csv))
  if (!file.exists(edges_csv)) stop(sprintf("load_graph_from_csv: edges file '%s' not found", edges_csv))

  nodes_df <- utils::read.csv(nodes_csv, stringsAsFactors = FALSE)
  edges_df <- utils::read.csv(edges_csv, stringsAsFactors = FALSE)

  build_polaris_graph(nodes_df, edges_df, prune_isolated = TRUE)
}

#' Load OD Demand Matrix from CSV
#'
#' @param od_csv Path to od_matrix.csv with origin row names and destination column headers
#' @return Named numeric matrix
#' @export
load_od_matrix_csv <- function(od_csv) {
  if (!file.exists(od_csv)) stop(sprintf("load_od_matrix_csv: file '%s' not found", od_csv))
  df <- utils::read.csv(od_csv, row.names = 1, check.names = FALSE)
  as.matrix(df)
}
