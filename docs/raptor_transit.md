# Polaris RAPTOR Public Transit Routing Specification

## 1. Overview & Data Primitives

RAPTOR (Round-Based Public Transit Routing) is a schedule-based multi-criteria transit routing algorithm. Unlike graph-based search algorithms that construct time-expanded or time-dependent networks, RAPTOR operates directly on timetable data organized by route patterns.

```
Round 0: Origin Stop Marked
Round 1: Stops reachable with 1 transit vehicle + walking transfers
Round 2: Stops reachable with 2 transit vehicles (1 transfer) + walking transfers
...
Round k: Stops reachable with k transit vehicles
```

---

## 2. Transit Network Representation

Polaris represents timetable feeds using high-density tabular arrays:
1. Stops: Array of physical transit stations with latitude, longitude, and stop identifier.
2. Route Patterns: Sequences of trips that visit the exact same ordered sequence of stops. Grouping trips into patterns allows linear array sweeps instead of searching individual trips.
3. Stop Times: Arrival and departure seconds relative to midnight for each stop along a trip. Trips within a pattern are sorted strictly chronologically by departure times at the first stop.
4. Footpaths: Pedestrian transfer edges between nearby stops within maximum walking distance (default 800m), precomputed using KD-Tree nearest neighbor queries.

---

## 3. Algorithmic Procedure

### 3.1 Round Execution
Let $\tau_k(p)$ denote the earliest arrival time at stop $p$ using at most $k$ transit trips.
At initialization:
$$\tau_0(p) = \infty \quad \forall p \ne s, \quad \tau_0(s) = t_{\text{departure}}$$
Mark source stop $s$.

In round $k$:
1. Accumulate Routes: Identify all route patterns $R$ that contain at least one stop marked in round $k-1$.
2. Traverse Routes: For each active route $R$:
   - Scan stops $p_i$ along $R$ starting from the earliest marked board stop.
   - Maintain the earliest reachable trip $T$ whose scheduled departure at the current stop is $\ge \tau_{k-1}(p_i)$.
   - For subsequent stops $p_j$, update arrival time:
     $$\tau_k(p_j) = \min \{ \tau_{k-1}(p_j), \text{arrivalTime}(T, p_j) \}$$
3. Relax Footpaths: For all stops $p$ updated in the current round, iterate over precomputed walking transfers $(p, p')$:
   $$\tau_k(p') = \min \{ \tau_k(p'), \tau_k(p) + \text{walkDuration}(p, p') \}$$
4. Mark updated stops for round $k+1$.
5. Terminate when no stops are updated or round limit (typically $k=4$ or $5$) is reached.

---

## 4. Range-RAPTOR Departure Time Windows

For flexible departure time queries $[t_{\text{start}}, t_{\text{end}}]$, Range-RAPTOR executes successive RAPTOR passes iterating backward through departure trips:
1. Evaluates all departure trips from origin stops within the window.
2. Self-prunes dominated itineraries using the current Pareto frontier.
3. Returns the complete set of non-dominated travel options across departure time, total journey duration, and number of transfers.
