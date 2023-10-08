# Polaris IO: Graph & Precomputed Index Binary Serialization
# Saves and restores compiled graph topologies, contraction hierarchies, and spatial indices

#' Save Polaris Graph to Disk
#'
#' @param graph polaris_graph object
#' @param file Target file path (.polaris or .rds)
#' @export
save_polaris_graph <- function(graph, file) {
  saveRDS(graph, file = file, compress = "xz")
  invisible(file)
}

#' Load Polaris Graph from Disk
#'
#' @param file File path
#' @return polaris_graph object
#' @export
load_polaris_graph <- function(file) {
  if (!file.exists(file)) stop(sprintf("load_polaris_graph: file '%s' not found", file))
  readRDS(file)
}

#' Save Contraction Hierarchies Index
#'
#' @param ch_index polaris_ch_index object
#' @param file File path
#' @export
save_ch_index <- function(ch_index, file) {
  saveRDS(ch_index, file = file, compress = "xz")
  invisible(file)
}

#' Load Contraction Hierarchies Index
#'
#' @param file File path
#' @return polaris_ch_index object
#' @export
load_ch_index <- function(file) {
  if (!file.exists(file)) stop(sprintf("load_ch_index: file '%s' not found", file))
  readRDS(file)
}
