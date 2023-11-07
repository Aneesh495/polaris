# Polaris Contraction Hierarchies Technical Specification

## 1. Algorithmic Overview

Contraction Hierarchies (CH) is a two-phase shortest path acceleration framework for road networks. In the offline preprocessing phase, vertices are contracted in order of topological importance, inserting shortcut edges to preserve shortest path distances among higher-ranked nodes. In the online query phase, a bidirectional upward Dijkstra search explores only edges leading to higher-ranked vertices, reducing search spaces by orders of magnitude.

```
       [Contracted Vertex v]
             ^       \
   edge1    /         \  edge2
           /           v
      [Node u] ------> [Node w]
              shortcut
```

---

## 2. Preprocessing & Node Ordering

### 2.1 Vertex Importance Heuristic
Vertex contraction order is computed using a composite priority function:
$$\text{Priority}(v) = 2 \cdot \text{EdgeDifference}(v) + \text{DeletedNeighbors}(v) + \text{ShortcutWeightRatio}(v)$$

- Edge Difference: Let $S(v)$ be the set of shortcuts required if $v$ is contracted, and $\text{deg}(v)$ be the current total in-and-out degree:
  $$\text{EdgeDifference}(v) = |S(v)| - \text{deg}(v)$$
  Prioritizing negative or small edge differences prevents graph density explosion.
- Deleted Neighbors: Number of already contracted neighbors adjacent to $v$. Promotes uniform contraction across geographic space.

### 2.2 Witness Path Search
For every pair of incoming edge $(u, v)$ and outgoing edge $(v, w)$, Polaris determines whether a shortcut $(u, w)$ is necessary. A shortcut is omitted if and only if there exists an alternative witness path $P$ in the remaining uncontracted graph such that:
$$\text{weight}(P) \le \text{weight}(u, v) + \text{weight}(v, w)$$

To maintain high preprocessing throughput, witness searches are localized:
- Max Hop Limit: Search terminates if hop depth exceeds $H = 5$.
- Max Weight Bound: Search terminates if priority queue minimum exceeds $\text{weight}(u, v) + \text{weight}(v, w)$.

---

## 3. Query Answering via Bidirectional Upward Search

### 3.1 Upward Search Graph
Given a query $(s, t)$:
- Forward Search ($G^\uparrow$): Begins at source $s$. Explores only edges $(u, v)$ where $\text{rank}(v) > \text{rank}(u)$.
- Backward Search ($G^\downarrow$): Begins at destination $t$. Explores only incoming edges $(v, w)$ where $\text{rank}(v) > \text{rank}(w)$.

Both searches operate on Directed Acyclic Graphs (DAGs) guaranteed by the total ordering of contraction ranks. Consequently, search frontiers cannot loop, and priority queues drain rapidly.

### 3.2 Tentative Shortest Distance & Meeting Node
A tentative minimum distance $\mu$ is initialized to $\infty$. Whenever a node $u$ is settled in the forward search and has also been reached in the backward search (or vice-versa):
$$\mu \leftarrow \min \{ \mu, d_f(u) + d_b(u) \}$$
The search terminates when the minimum priority in both queues meets or exceeds $\mu$.

---

## 4. Recursive Shortcut Unpacking

Shortcuts represent composite paths through contracted subgraphs. To reconstruct the complete physical road sequence:
1. Each shortcut record preserves `bypassed_node`, `edge1`, and `edge2`.
2. A recursive routine checks if an edge in the path is a shortcut:
   - If not a shortcut, emit the original edge ID.
   - If a shortcut, recursively unpack `edge1` followed by `edge2`.
3. The resulting edge sequence is strictly contiguous and preserves all original road attributes.

---

## 5. Performance Invariants

- Exactness: Shortest path distances computed via CH are bit-exact identical to standard Dijkstra.
- Speedup: Delivers 100x to 1,000x latency reduction over standard unidirectional Dijkstra on road networks.
- Verification: Formal Acceptance Gate PG09 validates zero distance divergence across randomized test topologies.
