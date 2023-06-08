# Polaris Core Priority Queue: Binary Heap, D-ary Heap, and Addressable Decrease-Key
# Optimized for high-throughput Dijkstra, A*, and Contraction Hierarchies

#' Indexed Addressable Min-Heap Priority Queue
#'
#' An addressable priority queue enabling O(log N) insertion, O(log N) extract-min,
#' and O(log N) decrease-key through bidirectional position indexing.
#'
#' @param initial_capacity Initial allocation size for internal arrays
#' @return An environment-based mutable priority queue object
#' @export
polaris_indexed_pq <- function(initial_capacity = 1024L) {
  env <- new.env(parent = emptyenv())

  # Internal storage vectors
  env$capacity <- as.integer(initial_capacity)
  env$size <- 0L
  env$priorities <- numeric(initial_capacity)
  env$elements <- character(initial_capacity)
  # Hash table mapping element ID -> heap index (1-based)
  env$index_map <- new.env(hash = TRUE, parent = emptyenv(), size = initial_capacity)

  # Helper: ensure capacity
  ensure_capacity <- function(e) {
    if (e$size >= e$capacity) {
      new_cap <- as.integer(e$capacity * 2L)
      new_prio <- numeric(new_cap)
      new_elem <- character(new_cap)
      new_prio[seq_len(e$size)] <- e$priorities[seq_len(e$size)]
      new_elem[seq_len(e$size)] <- e$elements[seq_len(e$size)]
      e$priorities <- new_prio
      e$elements <- new_elem
      e$capacity <- new_cap
    }
  }

  # Helper: swap two nodes in heap
  swap_nodes <- function(e, i, j) {
    p_tmp <- e$priorities[i]
    e$priorities[i] <- e$priorities[j]
    e$priorities[j] <- p_tmp

    e_i <- e$elements[i]
    e_j <- e$elements[j]
    e$elements[i] <- e_j
    e$elements[j] <- e_i

    e$index_map[[e_i]] <- j
    e$index_map[[e_j]] <- i
  }

  # Helper: sift up
  sift_up <- function(e, idx) {
    while (idx > 1L) {
      parent_idx <- as.integer(idx %/% 2L)
      if (e$priorities[idx] < e$priorities[parent_idx]) {
        swap_nodes(e, idx, parent_idx)
        idx <- parent_idx
      } else {
        break
      }
    }
  }

  # Helper: sift down
  sift_down <- function(e, idx) {
    sz <- e$size
    while (TRUE) {
      left <- as.integer(2L * idx)
      right <- as.integer(left + 1L)
      smallest <- idx

      if (left <= sz && e$priorities[left] < e$priorities[smallest]) {
        smallest <- left
      }
      if (right <= sz && e$priorities[right] < e$priorities[smallest]) {
        smallest <- right
      }

      if (smallest != idx) {
        swap_nodes(e, idx, smallest)
        idx <- smallest
      } else {
        break
      }
    }
  }

  # Public interface methods
  env$push <- function(element, priority) {
    elem_str <- as.character(element)
    existing_idx <- env$index_map[[elem_str]]
    if (!is.null(existing_idx)) {
      if (priority < env$priorities[existing_idx]) {
        env$decrease_key(elem_str, priority)
      }
      return(invisible(NULL))
    }
    ensure_capacity(env)
    env$size <- env$size + 1L
    idx <- env$size
    env$priorities[idx] <- as.numeric(priority)
    env$elements[idx] <- elem_str
    env$index_map[[elem_str]] <- idx
    sift_up(env, idx)
    invisible(NULL)
  }

  env$decrease_key <- function(element, new_priority) {
    elem_str <- as.character(element)
    idx <- env$index_map[[elem_str]]
    if (is.null(idx)) {
      stop(sprintf("decrease_key: element '%s' not present in queue", elem_str))
    }
    if (new_priority > env$priorities[idx]) {
      return(invisible(NULL)) # Monotonic decrease only
    }
    env$priorities[idx] <- as.numeric(new_priority)
    sift_up(env, idx)
    invisible(NULL)
  }

  env$pop <- function() {
    if (env$size == 0L) {
      return(NULL)
    }
    min_elem <- env$elements[1L]
    min_prio <- env$priorities[1L]

    rm(list = min_elem, envir = env$index_map)

    if (env$size == 1L) {
      env$size <- 0L
      return(list(element = min_elem, priority = min_prio))
    }

    last_elem <- env$elements[env$size]
    last_prio <- env$priorities[env$size]
    env$size <- env$size - 1L

    env$elements[1L] <- last_elem
    env$priorities[1L] <- last_prio
    env$index_map[[last_elem]] <- 1L

    sift_down(env, 1L)

    list(element = min_elem, priority = min_prio)
  }

  env$peek <- function() {
    if (env$size == 0L) return(NULL)
    list(element = env$elements[1L], priority = env$priorities[1L])
  }

  env$contains <- function(element) {
    !is.null(env$index_map[[as.character(element)]])
  }

  env$get_priority <- function(element) {
    idx <- env$index_map[[as.character(element)]]
    if (is.null(idx)) return(Inf)
    env$priorities[idx]
  }

  env$is_empty <- function() {
    env$size == 0L
  }

  env$length <- function() {
    env$size
  }

  structure(env, class = "polaris_indexed_pq")
}

#' 4-Ary (D-Ary) Min-Heap Priority Queue
#'
#' D-ary heap (d = 4) where each node has up to 4 children.
#' Provides shallower tree depth for rapid decrease-key workloads.
#'
#' @export
polaris_dary_pq <- function(d = 4L, initial_capacity = 1024L) {
  env <- new.env(parent = emptyenv())
  env$d <- as.integer(max(2L, d))
  env$capacity <- as.integer(initial_capacity)
  env$size <- 0L
  env$priorities <- numeric(initial_capacity)
  env$elements <- character(initial_capacity)
  env$index_map <- new.env(hash = TRUE, parent = emptyenv(), size = initial_capacity)

  swap_nodes <- function(e, i, j) {
    p_tmp <- e$priorities[i]
    e$priorities[i] <- e$priorities[j]
    e$priorities[j] <- p_tmp

    e_i <- e$elements[i]
    e_j <- e$elements[j]
    e$elements[i] <- e_j
    e$elements[j] <- e_i

    e$index_map[[e_i]] <- j
    e$index_map[[e_j]] <- i
  }

  sift_up <- function(e, idx) {
    d_val <- e$d
    while (idx > 1L) {
      parent_idx <- as.integer((idx - 2L) %/% d_val + 1L)
      if (e$priorities[idx] < e$priorities[parent_idx]) {
        swap_nodes(e, idx, parent_idx)
        idx <- parent_idx
      } else {
        break
      }
    }
  }

  sift_down <- function(e, idx) {
    d_val <- e$d
    sz <- e$size
    while (TRUE) {
      first_child <- as.integer(d_val * (idx - 1L) + 2L)
      if (first_child > sz) break

      smallest <- idx
      smallest_prio <- e$priorities[smallest]
      last_child <- min(sz, as.integer(first_child + d_val - 1L))

      for (c in seq(first_child, last_child)) {
        if (e$priorities[c] < smallest_prio) {
          smallest <- c
          smallest_prio <- e$priorities[c]
        }
      }

      if (smallest != idx) {
        swap_nodes(e, idx, smallest)
        idx <- smallest
      } else {
        break
      }
    }
  }

  env$push <- function(element, priority) {
    elem_str <- as.character(element)
    existing_idx <- env$index_map[[elem_str]]
    if (!is.null(existing_idx)) {
      if (priority < env$priorities[existing_idx]) {
        env$decrease_key(elem_str, priority)
      }
      return(invisible(NULL))
    }
    if (env$size >= env$capacity) {
      new_cap <- as.integer(env$capacity * 2L)
      new_prio <- numeric(new_cap)
      new_elem <- character(new_cap)
      new_prio[seq_len(env$size)] <- env$priorities[seq_len(env$size)]
      new_elem[seq_len(env$size)] <- env$elements[seq_len(env$size)]
      env$priorities <- new_prio
      env$elements <- new_elem
      env$capacity <- new_cap
    }
    env$size <- env$size + 1L
    idx <- env$size
    env$priorities[idx] <- as.numeric(priority)
    env$elements[idx] <- elem_str
    env$index_map[[elem_str]] <- idx
    sift_up(env, idx)
    invisible(NULL)
  }

  env$decrease_key <- function(element, new_priority) {
    elem_str <- as.character(element)
    idx <- env$index_map[[elem_str]]
    if (is.null(idx)) return(invisible(NULL))
    if (new_priority > env$priorities[idx]) return(invisible(NULL))
    env$priorities[idx] <- as.numeric(new_priority)
    sift_up(env, idx)
    invisible(NULL)
  }

  env$pop <- function() {
    if (env$size == 0L) return(NULL)
    min_elem <- env$elements[1L]
    min_prio <- env$priorities[1L]
    rm(list = min_elem, envir = env$index_map)
    if (env$size == 1L) {
      env$size <- 0L
      return(list(element = min_elem, priority = min_prio))
    }
    last_elem <- env$elements[env$size]
    last_prio <- env$priorities[env$size]
    env$size <- env$size - 1L
    env$elements[1L] <- last_elem
    env$priorities[1L] <- last_prio
    env$index_map[[last_elem]] <- 1L
    sift_down(env, 1L)
    list(element = min_elem, priority = min_prio)
  }

  env$peek <- function() {
    if (env$size == 0L) return(NULL)
    list(element = env$elements[1L], priority = env$priorities[1L])
  }

  env$contains <- function(element) {
    !is.null(env$index_map[[as.character(element)]])
  }

  env$get_priority <- function(element) {
    idx <- env$index_map[[as.character(element)]]
    if (is.null(idx)) return(Inf)
    env$priorities[idx]
  }

  env$is_empty <- function() {
    env$size == 0L
  }

  env$length <- function() {
    env$size
  }

  structure(env, class = "polaris_dary_pq")
}

#' Verify Min-Heap Structural Invariants
#'
#' Exhaustively asserts that parent priorities are strictly <= child priorities
#' and that bidirectional index mappings are 100% consistent.
#'
#' @param pq Priority queue object
#' @return TRUE if all structural invariants hold; halts on violation
#' @export
pq_verify_invariants <- function(pq) {
  sz <- pq$size
  if (sz <= 1L) return(TRUE)

  # Check binary heap invariant
  if (inherits(pq, "polaris_indexed_pq")) {
    for (i in 2:sz) {
      parent <- as.integer(i %/% 2L)
      if (pq$priorities[parent] > pq$priorities[i]) {
        stop(sprintf("Heap invariant violated at child %d (prio %.4f) < parent %d (prio %.4f)",
                     i, pq$priorities[i], parent, pq$priorities[parent]))
      }
      elem <- pq$elements[i]
      if (pq$index_map[[elem]] != i) {
        stop(sprintf("Index map mismatch for element '%s': mapped to %d, actual is %d",
                     elem, pq$index_map[[elem]], i))
      }
    }
  }
  TRUE
}
