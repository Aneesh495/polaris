# Polaris Isochrone: 2D Marching Squares Regular Grid Contouring
# Synthesizes smooth isoline rings across travel-time scalar fields

#' Marching Squares Isoline Generator
#'
#' Traces contour level boundaries on a 2D regular grid of travel-time values
#' using standard 16-case cell topological configurations.
#'
#' @param grid_matrix Numeric matrix of travel times at grid cell vertices
#' @param lats Numeric vector of grid row latitudes (strictly sorted)
#' @param lons Numeric vector of grid column longitudes (strictly sorted)
#' @param threshold Cutoff value in seconds or meters
#' @return List of line segments c(lat1, lon1, lat2, lon2)
#' @export
marching_squares_contour <- function(grid_matrix, lats, lons, threshold) {
  nrows <- nrow(grid_matrix)
  ncols <- ncol(grid_matrix)
  segments <- list()

  # Interpolate crossing coordinate along an edge
  interp_pt <- function(v1, v2, p1, p2) {
    if (abs(v2 - v1) < 1e-9) return((p1 + p2) / 2.0)
    frac <- (threshold - v1) / (v2 - v1)
    p1 + frac * (p2 - p1)
  }

  for (r in seq_len(nrows - 1L)) {
    for (c in seq_len(ncols - 1L)) {
      # 4 corners of cell:
      # Top-Left (TL), Top-Right (TR), Bottom-Right (BR), Bottom-Left (BL)
      v_tl <- grid_matrix[r, c]
      v_tr <- grid_matrix[r, c + 1L]
      v_br <- grid_matrix[r + 1L, c + 1L]
      v_bl <- grid_matrix[r + 1L, c]

      lat_top <- lats[r]
      lat_bot <- lats[r + 1L]
      lon_left <- lons[c]
      lon_right <- lons[c + 1L]

      # Compute 4-bit case index: TL * 8 + TR * 4 + BR * 2 + BL * 1
      case_idx <- (if (v_tl <= threshold) 8L else 0L) +
                  (if (v_tr <= threshold) 4L else 0L) +
                  (if (v_br <= threshold) 2L else 0L) +
                  (if (v_bl <= threshold) 1L else 0L)

      if (case_idx == 0L || case_idx == 15L) next

      # Edge intersection points
      # Top edge: between TL and TR
      t_lon <- interp_pt(v_tl, v_tr, lon_left, lon_right)
      p_top <- c(lat = lat_top, lon = t_lon)

      # Right edge: between TR and BR
      r_lat <- interp_pt(v_tr, v_br, lat_top, lat_bot)
      p_right <- c(lat = r_lat, lon = lon_right)

      # Bottom edge: between BL and BR
      b_lon <- interp_pt(v_bl, v_br, lon_left, lon_right)
      p_bot <- c(lat = lat_bot, lon = b_lon)

      # Left edge: between TL and BL
      l_lat <- interp_pt(v_tl, v_bl, lat_top, lat_bot)
      p_left <- c(lat = l_lat, lon = lon_left)

      # Lookup table for 16 Marching Squares cases
      if (case_idx == 1L || case_idx == 14L) {
        segments[[length(segments) + 1L]] <- c(p_left, p_bot)
      } else if (case_idx == 2L || case_idx == 13L) {
        segments[[length(segments) + 1L]] <- c(p_bot, p_right)
      } else if (case_idx == 3L || case_idx == 12L) {
        segments[[length(segments) + 1L]] <- c(p_left, p_right)
      } else if (case_idx == 4L || case_idx == 11L) {
        segments[[length(segments) + 1L]] <- c(p_top, p_right)
      } else if (case_idx == 5L) {
        segments[[length(segments) + 1L]] <- c(p_left, p_top)
        segments[[length(segments) + 1L]] <- c(p_bot, p_right)
      } else if (case_idx == 6L || case_idx == 9L) {
        segments[[length(segments) + 1L]] <- c(p_top, p_bot)
      } else if (case_idx == 7L || case_idx == 8L) {
        segments[[length(segments) + 1L]] <- c(p_left, p_top)
      } else if (case_idx == 10L) {
        segments[[length(segments) + 1L]] <- c(p_left, p_bot)
        segments[[length(segments) + 1L]] <- c(p_top, p_right)
      }
    }
  }

  segments
}
