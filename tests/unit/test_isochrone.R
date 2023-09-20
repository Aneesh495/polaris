# Unit Tests: Isochrones, Concave Hull, Point-in-Polygon, and Catchment

# Test 1: Isochrone Wavefront Propagation
g <- polaris_graph()
for (i in 1:10) {
  g$add_node(paste0("n", i), lat = 37.75 + (i * 0.005), lon = -122.45 + (i * 0.005))
}
for (i in 1:9) {
  # 500m edges at 50 km/h = 36 seconds each
  g$add_edge(paste0("e", i), paste0("n", i), paste0("n", i + 1),
             distance = 500.0, speed_limit = 50.0, oneway = FALSE)
}
g$build_csr()

# Query 100-second isochrone: should reach n1, n2, n3 (costs: 0, 36, 72; n4 is 108 > 100)
iso_pts <- polaris_isochrone_wavefront(g, origin_id = "n1", max_cost = 100.0, metric = "time")
assert_equal(nrow(iso_pts), 3L, "100s isochrone must contain exactly 3 vertices")
assert_true(all(iso_pts$cost <= 100.0), "All costs must be <= 100.0s")

# Test 2: Point-in-Polygon Ray Casting
# Unit square [0, 1] x [0, 1]
sq_lats <- c(0.0, 1.0, 1.0, 0.0, 0.0)
sq_lons <- c(0.0, 0.0, 1.0, 1.0, 0.0)

assert_true(point_in_polygon(0.5, 0.5, sq_lats, sq_lons), "Center (0.5, 0.5) is inside unit square")
assert_true(!point_in_polygon(1.5, 0.5, sq_lats, sq_lons), "(1.5, 0.5) is outside unit square")
assert_true(!point_in_polygon(-0.2, 0.5, sq_lats, sq_lons), "(-0.2, 0.5) is outside unit square")

# Test 3: Concave Hull Extraction
cloud <- data.frame(
  lat = c(37.75, 37.76, 37.76, 37.75, 37.755),
  lon = c(-122.45, -122.45, -122.44, -122.44, -122.445)
)
hull <- concave_hull(cloud, k = 3L)
assert_true(nrow(hull) >= 4L, "Concave hull produces closed polygon")
assert_equal(hull$lat[1], hull$lat[nrow(hull)], "Hull polygon is closed")

# Test 4: Marching Squares Contour
grid_mat <- matrix(c(
  10, 20, 30,
  20, 50, 70,
  30, 70, 90
), nrow = 3, ncol = 3, byrow = TRUE)
lats_grid <- c(37.77, 37.76, 37.75)
lons_grid <- c(-122.45, -122.44, -122.43)

segs <- marching_squares_contour(grid_mat, lats_grid, lons_grid, threshold = 25.0)
assert_true(length(segs) > 0L, "Marching squares generates isoline contour segments")
