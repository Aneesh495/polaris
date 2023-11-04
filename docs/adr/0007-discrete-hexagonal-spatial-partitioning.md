# ADR 0007: Hexagonal Discrete Global Grid Partitioning for Spatial Aggregation

## Status
Accepted

## Context
Spatial indexing, spatial binning, and catchment analysis require partitioning continuous geographic space into discrete polygonal cells. While standard rectangular latitude-longitude grids or Mercator tiles are computationally straightforward, they suffer from two major geometric defects:
1. Non-Uniform Neighbor Distances: In a square grid, orthogonal neighbors have distance $1.0$, while diagonal neighbors have distance $\sqrt{2} \approx 1.414$ (a $41\%$ distance asymmetry), introducing directional bias in spreading algorithms.
2. Topological Ambiguity: Square vertices meet at 4-way junctions, creating ambiguity regarding whether diagonal neighbors share an edge or a corner.

In contrast, regular hexagons tile the plane with complete symmetry: every cell has exactly 6 neighbors with identical centroid-to-centroid distances and identical shared boundary lengths.

We require a discrete global grid system based on regular hexagons to support uniform spatial partitioning, spatial clustering, and catchment wave propagation.

## Decision Drivers
1. Neighbor Equidistance: All adjacent cell centers must be equidistant.
2. Coordinate Simplicity: Efficient mathematical conversion between spherical WGS-84 coordinates and 2D hexagonal indices.
3. K-Ring Expansion: Fast topological ring queries for neighborhood searches.
4. Catchment Modeling: Consistent boundary formation for reachability and isochrone hulls.

## Considered Options
- Option 1: Planar Projected Hexagonal Grid with Axial Coordinates.
- Option 2: Geohash (Base-32 hierarchical rectangular grid).
- Option 3: Full Icosahedral Discrete Global Grid System (e.g., H3).
- Option 4: Quadtree / Morton Coding.

## Decision Outcome
Chosen Option: Option 1 (Planar Projected Hexagonal Grid with Axial Coordinates).

For urban, regional, and metropolitan routing domains, a planar hexagonal projection using axial coordinates $(q, r)$ provides mathematically elegant, $O(1)$ coordinate conversions and uniform topological adjacency without the heavyweight trigonometric overhead of recursive icosahedral aperture-7 decompositions.

## Technical Details

### 1. Hexagonal Geometry and Coordinate Systems
We adopt a flat-topped hexagonal orientation with cell radius $R$ (distance from center to vertex):
- Center-to-edge distance (apothem): $r_{\text{in}} = R \frac{\sqrt{3}}{2}$.
- Centroid spacing: Horizontal spacing is $\Delta x = \frac{3}{2} R$; vertical spacing is $\Delta y = \sqrt{3} R$.

### 2. Axial to Geographic Mapping
Using reference origin $(\text{lat}_0, \text{lon}_0)$, local meters $(x, y)$ map to axial coordinates $(q, r)$ via:
$$q = \frac{2}{3 R} x$$
$$r = \frac{-\frac{1}{3} x + \frac{\sqrt{3}}{3} y}{R}$$
Fractional axial coordinates are converted to integer cell indices using cube coordinate rounding to preserve the nearest Voronoi cell invariant:
$$x_{\text{cube}} = q, \quad z_{\text{cube}} = r, \quad y_{\text{cube}} = -x_{\text{cube}} - z_{\text{cube}}$$
$$\text{round}(x, y, z) \text{ subject to } x + y + z = 0$$

### 3. K-Ring Topological Query
A $k$-ring query around center cell $(q_0, r_0)$ returns all cells within topological distance $k$:
$$\text{CellCount}(k) = 1 + 3k(k + 1)$$
For $k=1$, 7 cells; for $k=2$, 19 cells; for $k=3$, 37 cells.
Because each neighbor is strictly equidistant, expansion rings form true isometric circles, providing isotropic spatial aggregation.

## Consequences

### Positive
- Zero directional bias: isotropic distance to all 6 adjacent neighbors.
- Exact $O(1)$ coordinate forward and inverse projections.
- Elegant multi-resolution hierarchical aggregation.

### Negative
- Pure hexagons do not perfectly subdivide into smaller hexagons (aperture-7 nesting requires rotated sub-grids). For strict hierarchical nesting, Polaris provides Geohash as a complementary rectangular system.
