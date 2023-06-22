# Polaris Core Geohash: Hierarchical Spatial Quantization & Base32 Codecs
# Interleaved spatial bitstrings, bounding box coverage, and 8-neighbor adjacency

GEOHASH_BASE32 <- strsplit("0123456789bcdefghjkmnpqrstuvwxyz", "")[[1]]
GEOHASH_DECODE_MAP <- setNames(seq_along(GEOHASH_BASE32) - 1L, GEOHASH_BASE32)

#' Encode Latitude and Longitude into Geohash String
#'
#' @param lat Latitude in degrees [-90.0, 90.0]
#' @param lon Longitude in degrees [-180.0, 180.0]
#' @param precision Number of Base32 characters (1 to 12, default 7)
#' @return Geohash character string
#' @export
geohash_encode <- function(lat, lon, precision = 7L) {
  precision <- as.integer(max(1L, min(12L, precision)))

  min_lat <- -90.0
  max_lat <- 90.0
  min_lon <- -180.0
  max_lon <- 180.0

  is_even <- TRUE # Even bits correspond to longitude, odd to latitude
  bit_count <- 0L
  char_val <- 0L
  hash_chars <- character(precision)
  char_idx <- 1L

  while (char_idx <= precision) {
    if (is_even) {
      mid <- (min_lon + max_lon) / 2.0
      if (lon >= mid) {
        char_val <- bitwOr(bitwShiftL(char_val, 1L), 1L)
        min_lon <- mid
      } else {
        char_val <- bitwShiftL(char_val, 1L)
        max_lon <- mid
      }
    } else {
      mid <- (min_lat + max_lat) / 2.0
      if (lat >= mid) {
        char_val <- bitwOr(bitwShiftL(char_val, 1L), 1L)
        min_lat <- mid
      } else {
        char_val <- bitwShiftL(char_val, 1L)
        max_lat <- mid
      }
    }

    is_even <- !is_even
    bit_count <- bit_count + 1L

    if (bit_count == 5L) {
      hash_chars[char_idx] <- GEOHASH_BASE32[char_val + 1L]
      char_idx <- char_idx + 1L
      bit_count <- 0L
      char_val <- 0L
    }
  }

  paste0(hash_chars, collapse = "")
}

#' Decode Geohash String to Bounding Box and Center Coordinate
#'
#' @param hash Geohash string
#' @return List with lat, lon, bbox, lat_error, lon_error
#' @export
geohash_decode <- function(hash) {
  chars <- strsplit(tolower(trimws(hash)), "")[[1]]
  min_lat <- -90.0
  max_lat <- 90.0
  min_lon <- -180.0
  max_lon <- 180.0

  is_even <- TRUE

  for (ch in chars) {
    val <- GEOHASH_DECODE_MAP[[ch]]
    if (is.null(val)) {
      stop(sprintf("geohash_decode: invalid Base32 geohash character '%s'", ch))
    }

    # Extract 5 bits from most-significant to least-significant
    for (bit_pos in 4:0) {
      mask <- bitwShiftL(1L, bit_pos)
      bit <- bitwAnd(val, mask) != 0L

      if (is_even) {
        mid <- (min_lon + max_lon) / 2.0
        if (bit) {
          min_lon <- mid
        } else {
          max_lon <- mid
        }
      } else {
        mid <- (min_lat + max_lat) / 2.0
        if (bit) {
          min_lat <- mid
        } else {
          max_lat <- mid
        }
      }
      is_even <- !is_even
    }
  }

  center_lat <- (min_lat + max_lat) / 2.0
  center_lon <- (min_lon + max_lon) / 2.0
  lat_err <- (max_lat - min_lat) / 2.0
  lon_err <- (max_lon - min_lon) / 2.0

  list(
    lat = center_lat,
    lon = center_lon,
    lat_error = lat_err,
    lon_error = lon_err,
    bbox = polaris_bbox(min_lat, min_lon, max_lat, max_lon)
  )
}

#' Compute 8 Neighboring Geohashes
#'
#' Finds the immediate spatial adjacent cells: North, South, East, West,
#' North-East, North-West, South-East, South-West.
#'
#' @param hash Target geohash
#' @return Named list of 8 neighbor geohashes
#' @export
geohash_neighbors <- function(hash) {
  dec <- geohash_decode(hash)
  lat_span <- dec$bbox$max_lat - dec$bbox$min_lat
  lon_span <- dec$bbox$max_lon - dec$bbox$min_lon
  prec <- nchar(hash)

  c_lat <- dec$lat
  c_lon <- dec$lon

  # Step offsets
  n_lat <- min(90.0, c_lat + lat_span)
  s_lat <- max(-90.0, c_lat - lat_span)
  e_lon <- ((c_lon + lon_span + 180.0) %% 360.0) - 180.0
  w_lon <- ((c_lon - lon_span + 180.0) %% 360.0) - 180.0

  list(
    north     = geohash_encode(n_lat, c_lon, prec),
    south     = geohash_encode(s_lat, c_lon, prec),
    east      = geohash_encode(c_lat, e_lon, prec),
    west      = geohash_encode(c_lat, w_lon, prec),
    northeast = geohash_encode(n_lat, e_lon, prec),
    northwest = geohash_encode(n_lat, w_lon, prec),
    southeast = geohash_encode(s_lat, e_lon, prec),
    southwest = geohash_encode(s_lat, w_lon, prec)
  )
}

#' Cover a Bounding Box with Geohash Cells
#'
#' Computes all unique geohashes of target precision required to fully cover
#' the specified geographic rectangle.
#'
#' @param bbox polaris_bbox object
#' @param precision Geohash precision level (1 to 12)
#' @return Character vector of geohashes
#' @export
geohash_cover_bbox <- function(bbox, precision = 6L) {
  # Estimate cell dimensions at target precision
  sample_hash <- geohash_encode(bbox$min_lat, bbox$min_lon, precision)
  sample_dec <- geohash_decode(sample_hash)
  lat_step <- (sample_dec$bbox$max_lat - sample_dec$bbox$min_lat) * 0.95
  lon_step <- (sample_dec$bbox$max_lon - sample_dec$bbox$min_lon) * 0.95

  lats <- seq(bbox$min_lat, bbox$max_lat, by = lat_step)
  if (lats[length(lats)] < bbox$max_lat) {
    lats <- c(lats, bbox$max_lat)
  }
  lons <- seq(bbox$min_lon, bbox$max_lon, by = lon_step)
  if (lons[length(lons)] < bbox$max_lon) {
    lons <- c(lons, bbox$max_lon)
  }

  hashes <- character(length(lats) * length(lons))
  idx <- 1L
  for (lt in lats) {
    for (ln in lons) {
      hashes[idx] <- geohash_encode(lt, ln, precision)
      idx <- idx + 1L
    }
  }

  unique(hashes)
}
