# Polaris IO: OpenStreetMap (OSM) XML & JSON Network Ingestion
# Extracts topological road networks, highway hierarchies, and directionality

# Default speed limits by OSM highway classification (km/h)
OSM_SPEED_DEFAULTS <- c(
  motorway        = 110.0,
  motorway_link   = 60.0,
  trunk           = 90.0,
  trunk_link      = 50.0,
  primary         = 60.0,
  primary_link    = 40.0,
  secondary       = 50.0,
  secondary_link  = 35.0,
  tertiary        = 40.0,
  tertiary_link   = 30.0,
  residential     = 30.0,
  living_street   = 15.0,
  service         = 20.0,
  unclassified    = 35.0
)

#' Parse OpenStreetMap XML File into Polaris Graph
#'
#' Streams an OSM XML file, extracting node coordinates and traversable highway ways.
#'
#' @param osm_file Path to .osm or .xml file
#' @return polaris_graph object with built CSR
#' @export
parse_osm_xml <- function(osm_file) {
  if (!file.exists(osm_file)) {
    stop(sprintf("parse_osm_xml: file '%s' not found", osm_file))
  }

  lines <- readLines(osm_file, warn = FALSE, encoding = "UTF-8")
  g <- polaris_graph()

  # Hash map of all parsed nodes: id -> polaris_coordinate
  all_nodes <- new.env(hash = TRUE, parent = emptyenv())

  in_way <- FALSE
  curr_way_id <- ""
  curr_way_nodes <- character(0)
  curr_way_tags <- list()
  edge_counter <- 0L

  for (line in lines) {
    trimmed <- trimws(line)

    # 1. Parse Node: <node id="123" lat="37.77" lon="-122.41".../>
    if (grepl("^<node ", trimmed)) {
      id_match <- regmatches(trimmed, regexec('id="([0-9]+)"', trimmed))[[1]]
      lat_match <- regmatches(trimmed, regexec('lat="([-0-9.]+)"', trimmed))[[1]]
      lon_match <- regmatches(trimmed, regexec('lon="([-0-9.]+)"', trimmed))[[1]]

      if (length(id_match) >= 2 && length(lat_match) >= 2 && length(lon_match) >= 2) {
        nd_id <- id_match[2]
        nd_lat <- as.numeric(lat_match[2])
        nd_lon <- as.numeric(lon_match[2])
        all_nodes[[nd_id]] <- polaris_coordinate(nd_lat, nd_lon)
      }
    }

    # 2. Start Way: <way id="456"...>
    if (grepl("^<way ", trimmed)) {
      in_way <- TRUE
      id_match <- regmatches(trimmed, regexec('id="([0-9]+)"', trimmed))[[1]]
      curr_way_id <- if (length(id_match) >= 2) id_match[2] else sprintf("way_%d", edge_counter)
      curr_way_nodes <- character(0)
      curr_way_tags <- list()
    }

    # 3. Inside Way: node references <nd ref="123"/> and tags <tag k="highway" v="primary"/>
    if (in_way) {
      if (grepl("^<nd ", trimmed)) {
        ref_match <- regmatches(trimmed, regexec('ref="([0-9]+)"', trimmed))[[1]]
        if (length(ref_match) >= 2) {
          curr_way_nodes <- c(curr_way_nodes, ref_match[2])
        }
      } else if (grepl("^<tag ", trimmed)) {
        k_match <- regmatches(trimmed, regexec('k="([^"]+)"', trimmed))[[1]]
        v_match <- regmatches(trimmed, regexec('v="([^"]+)"', trimmed))[[1]]
        if (length(k_match) >= 2 && length(v_match) >= 2) {
          curr_way_tags[[k_match[2]]] <- v_match[2]
        }
      } else if (grepl("^</way>", trimmed)) {
        # End of way: process highway segment
        in_way <- FALSE
        hwy_type <- curr_way_tags[["highway"]]

        if (!is.null(hwy_type) && length(curr_way_nodes) >= 2) {
          # Speed limit
          spd <- if (!is.null(curr_way_tags[["maxspeed"]])) {
            val <- as.numeric(sub("[^0-9.]", "", curr_way_tags[["maxspeed"]]))
            if (!is.na(val) && val > 0) val else 50.0
          } else {
            def_spd <- OSM_SPEED_DEFAULTS[[hwy_type]]
            if (!is.null(def_spd)) def_spd else 40.0
          }

          oneway_tag <- curr_way_tags[["oneway"]]
          is_oneway <- (!is.null(oneway_tag) && oneway_tag %in% c("yes", "1", "true")) ||
                       (hwy_type %in% c("motorway", "motorway_link"))

          # Add consecutive segments to graph
          for (k in seq_len(length(curr_way_nodes) - 1L)) {
            u_id <- curr_way_nodes[k]
            v_id <- curr_way_nodes[k + 1L]
            u_coord <- all_nodes[[u_id]]
            v_coord <- all_nodes[[v_id]]

            if (!is.null(u_coord) && !is.null(v_coord)) {
              # Ensure nodes are registered in graph
              g$add_node(u_id, u_coord$lat, u_coord$lon)
              g$add_node(v_id, v_coord$lat, v_coord$lon)

              d_m <- haversine_distance(u_coord$lat, u_coord$lon, v_coord$lat, v_coord$lon)
              edge_counter <- edge_counter + 1L
              e_name <- sprintf("osm_%s_%d", curr_way_id, k)

              g$add_edge(
                id = e_name,
                source = u_id,
                target = v_id,
                distance = d_m,
                speed_limit = spd,
                oneway = is_oneway,
                highway_type = hwy_type
              )
            }
          }
        }
      }
    }
  }

  g$build_csr()
  g
}
