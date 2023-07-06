# Unit Tests: WGS-84 Ellipsoidal Geodesics, Haversine, and Projections

# Test 1: Deg2Rad and Rad2Deg identity
assert_equal(deg2rad(180.0), pi, "180 degrees must equal pi radians")
assert_equal(rad2deg(pi / 2.0), 90.0, "pi/2 radians must equal 90 degrees")

# Test 2: Haversine on known baseline
# New York (40.7128, -74.0060) to London (51.5074, -0.1278)
d_hav <- haversine_distance(40.7128, -74.0060, 51.5074, -0.1278)
# Great circle distance is ~5570 km
assert_true(d_hav > 5560000 && d_hav < 5585000, "NY to London distance within expected bound")

# Test 3: Vincenty inverse on NY to London baseline
v_res <- vincenty_inverse(40.7128, -74.0060, 51.5074, -0.1278)
assert_true(v_res$converged, "Vincenty inverse must converge for NY to London")
assert_true(v_res$distance > 5570000 && v_res$distance < 5595000, "Vincenty distance accurate")
assert_true(v_res$initial_bearing > 50 && v_res$initial_bearing < 53, "Initial bearing to London northeast")

# Test 4: Coincident points
v_zero <- vincenty_inverse(37.7749, -122.4194, 37.7749, -122.4194)
assert_equal(v_zero$distance, 0.0, "Distance between identical coordinates must be zero")

# Test 5: Initial bearing cardinal directions
b_north <- initial_bearing(0.0, 0.0, 10.0, 0.0)
assert_equal(b_north, 0.0, "Due north must have 0 degree bearing")
b_east <- initial_bearing(0.0, 0.0, 0.0, 10.0)
assert_equal(b_east, 90.0, "Due east must have 90 degree bearing")
b_south <- initial_bearing(10.0, 0.0, 0.0, 0.0)
assert_equal(b_south, 180.0, "Due south must have 180 degree bearing")

# Test 6: Cross-track distance
# Point right on the arc has 0 cross-track distance
xt_zero <- cross_track_distance(5.0, 0.0, 0.0, 0.0, 10.0, 0.0)
assert_true(abs(xt_zero) < 1.0, "Point lying on meridian arc has zero cross-track distance")

# Point 1 degree east of meridian
xt_east <- cross_track_distance(5.0, 1.0, 0.0, 0.0, 10.0, 0.0)
assert_true(xt_east > 100000.0 && xt_east < 115000.0, "1 deg lon offset at 5 deg lat is ~110km")

# Test 7: Point-to-segment projection
proj_res <- project_point_to_segment(
  lat = 5.0, lon = 0.5,
  lat_start = 0.0, lon_start = 0.0,
  lat_end = 10.0, lon_end = 0.0
)
assert_true(proj_res$fraction > 0.45 && proj_res$fraction < 0.55, "Projection fraction near midpoint")
assert_equal(proj_res$proj_lon, 0.0, "Projected longitude must be on segment meridian", tol = 1e-4)

# Test 8: Polyline cumulative length
pts <- list(
  polaris_coordinate(0.0, 0.0),
  polaris_coordinate(0.0, 1.0),
  polaris_coordinate(0.0, 2.0)
)
poly_len <- polyline_length(pts)
assert_true(poly_len > 220000.0 && poly_len < 225000.0, "2 deg equatorial span ~222.6km")
