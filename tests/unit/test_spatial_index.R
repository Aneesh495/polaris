# Unit Tests: 2D Spatial R-Tree, KD-Tree, Geohash, and Hexagonal Grid

# Test 1: Bounding Box Area and Intersection
b1 <- polaris_bbox(10.0, 10.0, 20.0, 20.0)
b2 <- polaris_bbox(15.0, 15.0, 25.0, 25.0)
b3 <- polaris_bbox(30.0, 30.0, 40.0, 40.0)

assert_equal(bbox_area(b1), 100.0, "Bounding box area calculation 10x10=100")
assert_true(bbox_intersects(b1, b2), "b1 and b2 overlap and must intersect")
assert_true(!bbox_intersects(b1, b3), "b1 and b3 are disjoint and must not intersect")

# Test 2: Spatial R-Tree Insertion and Search
rt <- polaris_rtree(max_entries = 4L, min_entries = 2L)
# Insert 30 spatial features
for (i in 1:30) {
  lat <- 37.0 + (i * 0.05)
  lon <- -122.0 + (i * 0.05)
  box <- polaris_bbox(lat - 0.01, lon - 0.01, lat + 0.01, lon + 0.01)
  rt$insert(id = paste0("feat_", i), bbox = box, data = list(val = i))
}

assert_equal(rt$count, 30L, "R-Tree must contain 30 entries")

# Query box overlapping entries 5 to 10
q_box <- polaris_bbox(37.20, -121.80, 37.55, -121.45)
matches <- rt$search(q_box)
assert_true(length(matches) >= 5, "Query box must return matching entries")

# k-NN search on R-Tree
knn_res <- rt$knn(lat = 37.25, lon = -121.75, k = 3L)
assert_equal(length(knn_res), 3L, "k-NN on R-Tree must return 3 nearest neighbors")
assert_true(knn_res[[1]]$distance <= knn_res[[2]]$distance, "k-NN results must be sorted by distance")

# Test 3: KD-Tree Construction and Nearest Query
pts <- matrix(c(
  37.7749, -122.4194, # SF
  34.0522, -118.2437, # LA
  40.7128, -74.0060,  # NY
  47.6062, -122.3321  # Seattle
), byrow = TRUE, ncol = 2)
colnames(pts) <- c("lat", "lon")
ids <- c("SF", "LA", "NY", "SEA")

kd <- polaris_kdtree(pts, ids = ids)
nearest_sf <- kd$nearest(37.78, -122.40)
assert_equal(nearest_sf$id, "SF", "Point near SF must match SF as nearest neighbor")

nearest_bos <- kd$nearest(42.3601, -71.0589) # Boston -> nearest is NY
assert_equal(nearest_bos$id, "NY", "Point in Boston must match NY as nearest neighbor")

# Radius search
within_ca <- kd$radius_search(36.0, -120.0, radius_meters = 400000.0) # ~400km
ca_ids <- vapply(within_ca, function(x) x$id, character(1))
assert_true("SF" %in% ca_ids && "LA" %in% ca_ids, "SF and LA within 400km of Central Valley")
assert_true(!("NY" %in% ca_ids), "NY not in California radius search")

# Test 4: Geohash Encoding / Decoding Roundtrip
gh <- geohash_encode(37.7749, -122.4194, precision = 8L)
assert_equal(nchar(gh), 8L, "Encoded geohash length must equal precision")
dec <- geohash_decode(gh)
assert_true(abs(dec$lat - 37.7749) < 0.001, "Decoded lat matches original within precision")
assert_true(abs(dec$lon - (-122.4194)) < 0.001, "Decoded lon matches original within precision")

# Geohash 8-neighbors
nbrs <- geohash_neighbors(gh)
assert_equal(length(nbrs), 8L, "Must have exactly 8 neighbors")
assert_true(all(vapply(nbrs, nchar, integer(1)) == 8L), "All neighbors must have same precision")

# Test 5: Hexagonal Global Grid System
hex_id <- geo_to_hex(37.7749, -122.4194, resolution = 7L)
assert_true(grepl("^h_7_", hex_id), "Hex ID must start with h_7_")
hex_center <- hex_to_geo(hex_id)
assert_true(abs(hex_center$lat - 37.7749) < 0.05, "Hex center latitude near original")

# K-ring size invariant: (3 * k * (k + 1)) + 1
kring_1 <- hex_kring(hex_id, k = 1L)
assert_equal(length(kring_1), 7L, "1-ring must contain exactly 7 cells")
kring_2 <- hex_kring(hex_id, k = 2L)
assert_equal(length(kring_2), 19L, "2-ring must contain exactly 19 cells")

# Hex boundary polygon
poly <- hex_boundary(hex_id)
assert_equal(nrow(poly), 7L, "Hex boundary must have 7 coordinate rows (6 vertices closed)")
assert_equal(poly$lat[1], poly$lat[7], "Hex boundary polygon must be closed")
