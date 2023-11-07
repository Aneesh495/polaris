# Polaris Spatial Indexing Manual

## 1. Multi-Index Spatial Architecture

High-throughput spatial graph processing requires specialized data structures tailored to distinct geometric operations. Polaris integrates four distinct spatial indexing systems:

| Index Name | Geometry | Primary Operation | Complexity | Source File |
|---|---|---|---|---|
| Spatial R-Tree | Minimum Bounding Boxes (MBR) | Window intersection, segment retrieval | $O(\log_M N)$ query | `R/core/spatial_index.R` |
| 2D K-D Tree | Points $(x, y)$ | Exact $k$-Nearest Neighbors | $O(\log N)$ average | `R/core/spatial_kdtree.R` |
| Geohash Index | Base-32 String Encodings | Spatial hashing, prefix matching | $O(1)$ encode/decode | `R/core/spatial_geohash.R` |
| Hexagonal DGGS | Flat-topped Hexagons $(q, r)$ | Isotropic aggregation, $k$-ring expansion | $O(1)$ binning | `R/core/spatial_hex.R` |

---

## 2. Spatial R-Tree Implementation Details

### 2.1 Bounding Box Pruning
Nodes store Minimum Bounding Rectangles (MBR) defined by $(\text{min\_lat}, \text{min\_lon}, \text{max\_lat}, \text{max\_lon})$.
Intersection between two boxes $B_1$ and $B_2$ is evaluated via non-overlap tests:
$$\neg (\text{max\_lat}_1 < \text{min\_lat}_2 \lor \text{min\_lat}_1 > \text{max\_lat}_2 \lor \text{max\_lon}_1 < \text{min\_lon}_2 \lor \text{min\_lon}_1 > \text{max\_lon}_2)$$

### 2.2 Quadratic Node Split
When node entries exceed `max_entries` (default 8):
1. Pick Seeds: Find the pair of entries whose enclosing bounding box maximizes dead area:
   $$\text{dead\_area} = \text{area}(\text{combine}(e_1, e_2)) - \text{area}(e_1) - \text{area}(e_2)$$
2. Distribute Remaining Entries: For each unassigned entry, evaluate the area enlargement required to add it to group 1 vs group 2, assigning it to the group with minimal expansion.

---

## 3. K-D Tree Implementation Details

The 2D K-D tree recursively partitions coordinates by alternating between latitude (dimension 0) and longitude (dimension 1) at median splits:
- Construction: $O(N \log N)$ using median-of-medians or sorting.
- Branch-and-Bound Nearest Neighbor: Explores the closer subtree first; prunes the alternative subtree whenever the orthogonal distance to the splitting hyperplane exceeds current nearest neighbor distance.

---

## 4. Geohash Spatial Encoding

Geohash interleaves bits from longitude and latitude into a binary string, which is then mapped to base-32 characters:
- 32-character alphabet: `0123456789bcdefghjkmnpqrstuvwxyz` (omits `a`, `i`, `l`, `o` to prevent OCR confusion).
- Precision 7: Bounding box size $\approx 153\text{m} \times 153\text{m}$.
- Prefix property: Spatial proximity is preserved in string prefixes, allowing spatial range queries via string matching.

---

## 5. Hexagonal DGGS Implementation

Flat-topped hexagons use axial coordinates $(q, r)$ where:
- Ring Expansion: Cell count for ring $k$ is $1 + 3k(k+1)$.
- All 6 immediate neighbors are equidistant ($D = \sqrt{3} R$).
- Eliminates the diagonal distance bias inherent in square grids, providing isotropic wave propagation for isochrones.
