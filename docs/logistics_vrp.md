# Polaris Logistics & Vehicle Routing Specification

## 1. Problem Formulation: Capacitated VRP with Time Windows (VRPTW)

The Vehicle Routing Problem with Time Windows (VRPTW) models dispatching a fleet of homogeneous vehicles of capacity $Q$ from a central depot to service $N$ customers with demands $q_i$, service durations $s_i$, and delivery time windows $[e_i, l_i]$.

```
                      [Central Depot]
                      /      |      \
                     v       v       v
                 [Route 1] [Route 2] [Route 3]
                   o-o-o     o-o       o-o-o-o
```

Objective:
$$\min \sum_{k \in K} \sum_{i} \sum_{j} c_{ij} x_{ijk}$$
Subject to:
- Every customer is visited exactly once.
- Total demand on any route $k$ does not exceed vehicle capacity $Q$:
  $$\sum_{i \in R_k} q_i \le Q$$
- Arrival at customer $i$ respects time windows:
  $$e_i \le a_i \le l_i$$
  If a vehicle arrives before $e_i$, it waits until $e_i$. Arrival after $l_i$ violates feasibility.

---

## 2. Clarke-Wright Savings Construction Heuristic

Polaris constructs initial feasible vehicle tours using the classical Clarke-Wright savings heuristic:

1. Back-and-Forth Baseline: Initially assign every customer $i$ to a dedicated route $(\text{Depot} \to i \to \text{Depot})$.
2. Savings Evaluation: For every customer pair $(i, j)$, calculate the distance saved by merging two routes:
   $$S_{ij} = c_{\text{depot}, i} + c_{j, \text{depot}} - c_{ij}$$
3. Sort candidate savings pairs in descending order: $S_{i_1, j_1} \ge S_{i_2, j_2} \ge \dots$
4. Merge Feasibility: Merge routes containing $i$ and $j$ if:
   - $i$ and $j$ are currently endpoints of separate routes (adjacent to depot).
   - The combined route load $q(R_1) + q(R_2) \le Q$.
   - Time window constraints remain feasible across the merged sequence.

---

## 3. Local Search & Improvement Operators

To refine initial heuristic tours, Polaris applies iterative neighborhood search operators:

### 3.1 2-Opt Intra-Route Reversal
Exchanges two non-adjacent edges $(u, v)$ and $(w, z)$ within the same route by reversing the intervening customer sub-sequence:
$$\Delta c = (c_{uw} + c_{vz}) - (c_{uv} + c_{wz})$$
If $\Delta c < 0$ and time windows remain feasible, the move is committed.

### 3.2 Inter-Route Relocate & Swap
- Relocate: Moves customer $i$ from route $R_1$ into route $R_2$ at the insertion position yielding maximum distance reduction.
- Swap: Exchanges customer $i \in R_1$ with customer $j \in R_2$.

---

## 4. Tabu Search Metaheuristic

To escape local minima, Polaris provides a Tabu Search metaheuristic:
- Neighborhood: Best-improving relocate and 2-opt moves across all active routes.
- Tabu List: Memorizes recent moves for tenure $T$ (default 10 iterations) to prevent cycling.
- Aspiration Criterion: A tabu move is accepted if it produces a solution superior to the historical global best.
