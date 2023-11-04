# ADR 0003: Round-Based Public Transit Routing via RAPTOR

## Status
Accepted

## Context
Public transit networks differ fundamentally from road networks: transit edges are not available continuously. Instead, transit connections are governed by discrete timetables with scheduled departure times, variable headways, and operational calendars.

Standard graph algorithms (such as time-expanded or time-dependent Dijkstra) suffer from extreme graph blowup: a medium-sized transit network expands into tens of millions of time-stamped nodes and edges. Search overhead and priority queue operations severely degrade query performance.

We require a transit routing algorithm that operates directly on timetable schedules without priority queues, while natively computing Pareto-optimal trade-offs between arrival time and number of transfers.

## Decision Drivers
1. Multi-Criteria Pareto Optimization: Simultaneously minimize arrival time and transfer count.
2. Memory Footprint: Avoid time-expanded graph explosion.
3. Priority Queue Elimination: Eliminate heap overhead by organizing searches in rounds.
4. Range Queries: Support departure time windows (e.g., depart anytime between 08:00 and 09:00).
5. Intermodal Transfers: Seamlessly incorporate pedestrian walking transfers between nearby stops.

## Considered Options
- Option 1: RAPTOR (Round-Based Public Transit Routing) (Delling et al., 2012).
- Option 2: Time-Expanded Dijkstra.
- Option 3: Time-Dependent Dijkstra.
- Option 4: Connection Scan Algorithm (CSA) (Dibbelt et al., 2013).

## Decision Outcome
Chosen Option: Option 1 (RAPTOR).

RAPTOR evaluates routes round by round, where round $k$ computes the earliest arrival times using at most $k$ transit trips. It operates directly on organized route patterns (sequences of trips sharing identical stop sequences), achieving dramatic cache locality and zero priority queue operations.

## Technical Details

### 1. Data Organization
Transit data from GTFS (General Transit Feed Specification) is decomposed into:
- Stops: Spatial locations with transfer neighborhoods.
- Routes: Unique ordered sequences of stops.
- Trips: Individual vehicles traversing a route, sorted strictly chronologically by departure times.
- Stop Times: Scheduled arrival and departure seconds relative to midnight.

### 2. Algorithmic Workflow
1. Initialization: Earliest arrival time array $\tau(p) \leftarrow \infty$ for all stops $p$. Set $\tau(s) \leftarrow t_{\text{dep}}$. Mark source stop $s$.
2. Round $k$ Execution:
   - Identify active routes containing at least one marked stop from round $k-1$.
   - For each active route, scan stops along the route sequence from the earliest marked board stop.
   - Maintain the earliest reachable trip that departs after the current arrival time at the board stop.
   - For downstream stops $p_i$, update $\tau_k(p_i)$ if the trip arrives earlier than existing labels.
   - Relax footpaths: for all updated stops, propagate walking transfers to neighboring stops.
   - Mark newly reached stops.
3. Stopping Criteria: Terminate when no stops are marked or round count reaches threshold (typically $k=4$ or $5$).

### 3. Range-RAPTOR Extension
To support flexible departure windows $[t_{\text{start}}, t_{\text{end}}]$, Range-RAPTOR iterates backwards through departure trips, maintaining the Pareto frontier across departure times and total transit durations.

## Consequences

### Positive
- Zero priority queue overhead: inner loops are linear array scans.
- Exact Pareto frontier: returns all non-dominated itineraries (e.g., faster arrival vs fewer transfers).
- Highly compact memory footprint: timetable arrays require a fraction of time-expanded graph memory.

### Negative
- Footpath relaxation requires spatial preprocessing to compute all walk transfers below distance limits (typically 500m to 1km). Handled efficiently via spatial KD-Tree.
