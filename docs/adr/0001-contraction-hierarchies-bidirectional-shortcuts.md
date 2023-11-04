# ADR 0001: Contraction Hierarchies with Shortcut Unpacking for Highway Speedups

## Status
Accepted

## Context
Standard shortest path algorithms such as Dijkstra, Bidirectional Dijkstra, and A* scale with network size $O(|E| + |V| \log |V|)$. On regional and continental road networks containing millions of directed edges, point-to-point path calculation incurs latencies ranging from 15 milliseconds to several seconds. This latency profile is unacceptable for interactive navigation, multi-destination distance matrices ($N \times M$), and high-frequency dispatch simulations.

We require a routing acceleration technique that delivers query answering latencies on the order of 10 to 100 microseconds while maintaining bit-exact path distance equivalence with standard Dijkstra.

## Decision Drivers
1. Query Latency: Queries must execute in sub-millisecond time.
2. Metric Correctness: Zero tolerance for heuristic error or distance deviations from Dijkstra.
3. Preprocessing Tractability: Node ordering and shortcut insertion must execute within reasonable memory bounds.
4. Path Reconstruction: The system must unpack composite shortcuts into original physical road segments.
5. Implementation Feasibility: Pure R reference capability with native C acceleration.

## Considered Options
- Option 1: Contraction Hierarchies (CH) (Geisberger et al., 2008).
- Option 2: Transit Node Routing (TNR) (Bast et al., 2007).
- Option 3: Hub Labeling (HL) (Abraham et al., 2011).
- Option 4: Pure A* with ALT (A*, Landmarks, Triangle Inequality) (Goldberg and Harrelson, 2005).

## Decision Outcome
Chosen Option: Option 1 (Contraction Hierarchies).

Contraction Hierarchies provides the optimal balance of preprocessing time ($O(|V| \log |V|)$), storage overhead (modest shortcut edge count), and query acceleration (up to 1,000x speedup over Dijkstra). Furthermore, bidirectional upward search on DAGs eliminates the need to explore downward arcs, drastically pruning search spaces.

## Technical Details

### 1. Node Ordering Heuristic
Vertices are contracted according to an importance priority function:
$$\text{Priority}(v) = 2 \cdot \text{EdgeDifference}(v) + \text{DeletedNeighbors}(v) + \text{ShortcutWeightRatio}(v)$$
Where:
- $\text{EdgeDifference}(v) = |\text{ShortcutsNeeded}(v)| - (|\text{InEdges}(v)| + |\text{OutEdges}(v)|)$
- $\text{DeletedNeighbors}(v)$ counts adjacent nodes already contracted.

### 2. Witness Search
Before creating a shortcut edge $(u, w)$ bypassing contracted node $v$, a localized Dijkstra search (witness search) bounded by maximum hop limit $H=5$ and max cost $c(u, v) + c(v, w)$ is performed. If an alternative path exists in the remaining graph with cost $\le c(u, v) + c(v, w)$, the shortcut is omitted.

### 3. Upward Query Search
During query execution from source $s$ to destination $t$:
- Forward search traverses only edges leading to nodes with higher contraction rank: $\text{rank}(v) > \text{rank}(u)$.
- Backward search traverses incoming edges leading to nodes with higher contraction rank: $\text{rank}(u) > \text{rank}(v)$.
- The meeting vertex $m = \arg\min \{ d_f(w) + d_b(w) \}$ establishes the exact minimum distance.

### 4. Recursive Shortcut Unpacking
Each shortcut edge stores references to its constituent edges `edge1` and `edge2` along with the bypassed node. A recursive unpacking traversal traverses shortcut branches down to base road segments, ensuring lossless edge identifier reconstruction.

## Consequences

### Positive
- Sub-millisecond point-to-point routing queries.
- Zero distance approximation error: guaranteed identical to Dijkstra.
- Substantially faster distance matrix computation for logistics solvers.

### Negative
- Requires an offline preprocessing phase prior to query execution.
- Dynamic road closures or weight changes require either local contraction updates or fallback to A*.
