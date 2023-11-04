# ADR 0005: Line-Graph Dual Transformation for Turn Restrictions and Maneuver Costs

## Status
Accepted

## Context
Standard shortest path algorithms operate on primal graphs where nodes represent physical intersections and edges represent road links. However, realistic navigation requires accounting for turn restrictions (e.g., prohibited left turns, no U-turns) and turn penalties (e.g., delay incurred waiting across oncoming traffic or traversing complex signalized intersections).

In a primal graph formulation, node states do not record the incoming edge used to reach the node, making it impossible to enforce turn penalties without violating Bellman's principle of optimality or complicating state spaces with ad-hoc heuristics.

We require a rigorous mathematical representation for turn restrictions and intersection delays that integrates seamlessly with existing Dijkstra and A* search engines.

## Decision Drivers
1. Strict Enforcement: Prohibited turns must never be traversed.
2. Maneuver Delays: Support distinct delays for left turns, right turns, straight maneuvers, and U-turns based on intersection angles.
3. Search Compatibility: The transformed representation must support standard routing algorithms without modification.
4. Lossless Projection: Paths computed on the transformed graph must map back unambiguously to physical road sequences.

## Considered Options
- Option 1: Dual Graph (Line Graph) Transformation (Winter, 2002).
- Option 2: State-Augmented Dijkstra (maintaining `(node, incoming_edge)` in priority queues).
- Option 3: Post-Processing Path Repair (re-routing when a turn violation is encountered).

## Decision Outcome
Chosen Option: Option 1 (Dual Graph Transformation).

The line graph $L(G)$ transforms every physical edge $e \in E(G)$ into a dual vertex $v_e \in V(L(G))$. Directed edges in $L(G)$ represent legal transitions from an incoming link $e_1 = (u, v)$ to an outgoing link $e_2 = (v, w)$. Forbidden turns simply correspond to omitted dual edges, and turn delays are added directly to dual edge weights.

## Technical Details

### 1. Maneuver Classification via Angular Geometry
Given incoming edge $e_1 = (u, v)$ with bearing $\theta_1$ and outgoing edge $e_2 = (v, w)$ with bearing $\theta_2$, the turn deflection angle is:
$$\Delta\theta = ((\theta_2 - \theta_1 + 180^\circ) \bmod 360^\circ) - 180^\circ$$
Maneuver categories:
- Straight: $|\Delta\theta| \le 30^\circ$ (baseline cost: $0.0$ s).
- Slight Right / Left: $30^\circ < |\Delta\theta| \le 60^\circ$ (cost: $2.0$ s).
- Right Turn: $60^\circ < \Delta\theta \le 120^\circ$ (cost: $4.0$ s).
- Left Turn: $-120^\circ \le \Delta\theta < -60^\circ$ (cost: $8.0$ s, reflecting cross-traffic delay).
- Sharp Turn / U-Turn: $|\Delta\theta| > 120^\circ$ (cost: $15.0$ s or prohibited).

### 2. Dual Graph Construction
1. For every edge $e = (u, v) \in E(G)$, instantiate dual node $e$.
2. For every pair of adjacent edges $e_1 = (u, v)$ and $e_2 = (v, w)$:
   - Check turn restriction table. If transition $(e_1, e_2)$ is prohibited, skip edge creation.
   - Otherwise, calculate turn delay $\tau_{\text{turn}}(e_1, e_2)$.
   - Add dual edge $(e_1, e_2)$ with weight:
     $$W(e_1, e_2) = \text{weight}(e_2) + \tau_{\text{turn}}(e_1, e_2)$$
3. The dual graph is compiled into standard Compressed Sparse Row (CSR) representation.

### 3. Querying on the Dual Graph
To route from location $A$ on edge $e_s$ to location $B$ on edge $e_t$:
- Dual Dijkstra search executes from source node $e_s$ to destination node $e_t$.
- The resulting sequence of dual nodes corresponds exactly to the sequence of primal edges in the optimal route.

## Consequences

### Positive
- Strict, zero-leak turn restriction enforcement.
- Realistic navigation times that account for intersection delays.
- Standard routing kernels (Dijkstra, A*, CH) execute on $L(G)$ without modification.

### Negative
- Increases vertex count to $|E|$ and edge count to $\sum \text{deg}^+(v) \cdot \text{deg}^-(v)$. However, road intersection degrees are small (average degree $\approx 3.2$), keeping the expansion well within memory limits.
