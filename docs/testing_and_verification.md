# Polaris Testing and Verification Framework

## 1. Multi-Tier Verification Philosophy

Polaris implements a multi-layer verification methodology designed to guarantee mathematical correctness, algorithmic exactness, and numerical stability:

```
[Tier 1] Unit Test Suite (11 test files, 100+ assertions)
   └── Validates atomic components (geodesy, heaps, trees, Dijkstra, Viterbi, RAPTOR)
[Tier 2] Native-Pure Equivalence Integration Suite
   └── Bit-level verification (.Call C kernel vs Pure-R reference implementations)
[Tier 3] 16 Formal Acceptance Gates (PG01 - PG16)
   └── Cryptographically exportable evidence bundle of mathematical invariants
[Tier 4] 14 Independent Negative Controls (NC01 - NC14)
   └── Adversarial auditing proving that tampered or falsified evidence is rejected
[Tier 5] Continuous Typography & Style Linter
   └── Enforces zero em/en dash invariant across all code, tests, and documentation
```

---

## 2. The 16 Formal Acceptance Gates (PG01 to PG16)

The verification campaign (`tools/run_acceptance.R`) executes 16 formal gates covering the entire theoretical surface area:

| Gate ID | Gate Name | Subsystem | Validation Metric | Pass Threshold |
|---|---|---|---|---|
| PG01 | WGS-84 Geodesic Precision | Geodesy | Vincenty vs Haversine distance error | $< 5000.0$ m |
| PG02 | Min-Heap Structural Invariant | Data Structures | Parent-child key comparison violations | $== 0$ |
| PG03 | Spatial R-Tree Bounding Search | Indexing | Spatial bounding query intersection count | $\ge 1$ |
| PG04 | KD-Tree Nearest Query | Indexing | Euclidean nearest neighbor distance | $> 0.0$ |
| PG05 | Geohash Codec Round-Trip | Indexing | Encode-decode coordinate reconstruction error | $< 0.001^\circ$ |
| PG06 | Hexagonal K-Ring Step Count | Indexing | Topological ring cell count $1 + 3k(k+1)$ | $== 37$ (for $k=3$) |
| PG07 | Tarjan SCC Partitioning | Graph Core | Strongly Connected Component partition count | $== 2$ |
| PG08 | Multi-Algorithmic Route Equivalence | Routing | Max distance divergence: Dijkstra vs A* vs Bidirectional | $< 10^{-4}$ |
| PG09 | Contraction Hierarchies Bit-Exactness | Routing | Max distance divergence: CH vs Dijkstra | $< 10^{-4}$ |
| PG10 | Dual-Graph Turn Restriction | Routing | Prohibited turn edge omitted from dual path | $== 1$ |
| PG11 | Viterbi HMM Trace Matching | Matching | Snapped GPS ping count on ground-truth links | $== 3$ |
| PG12 | Kalman Filter Outlier Detection | Matching | Sensor outlier flag count ($> 3\sigma$) | $\ge 1$ |
| PG13 | RAPTOR Timetable Routing | Transit | Pareto-optimal non-dominated itinerary count | $\ge 1$ |
| PG14 | Frank-Wolfe Equilibrium Convergence | Traffic | Relative gap objective metric | $< 0.05$ |
| PG15 | Capacitated VRP Load Feasibility | Logistics | Vehicle capacity overage count | $== 0$ |
| PG16 | Zero Em/En Dash Invariant | Typography | Forbidden Unicode dash character occurrences | $== 0$ |

---

## 3. The 14 Negative Controls (NC01 to NC14)

The independent evidence auditor (`tools/verify_evidence.R`) executes 14 negative controls to prove the evidence bundle cannot be faked:

- NC01: Missing File Trap (safely rejects non-existent input files).
- NC02: Malformed JSON Syntax Trap (safely catches and rejects truncated or invalid JSON).
- NC03: Schema Key Presence (validates presence of all 7 mandatory top-level schema keys).
- NC04: Gate Count Cardinality (verifies parsed gate count matches `total_gates == 16`).
- NC05: Arithmetic Gate Sum Invariant (verifies `gates_passed + gates_failed == total_gates`).
- NC06: Pass/Fail Flag Consistency (validates `all_passed == (gates_failed == 0)`).
- NC07: Exhaustive Gate Sequence (verifies presence of all IDs PG01 through PG16).
- NC08: Gate Uniqueness Invariant (verifies zero duplicate gate entries).
- NC09: Metric Sign Bounds (verifies all recorded physical metrics are $\ge 0.0$).
- NC10: Equilibrium Gap Threshold Trap (verifies PG14 relative gap $< 0.05$).
- NC11: Priority Queue Zero-Violation Trap (verifies PG02 heap violations $== 0$).
- NC12: Typography Invariant Trap (verifies PG16 forbidden dash count $== 0$).
- NC13: ISO-8601 Timestamp Sanity (validates standard UTC date-time syntax).
- NC14: Adversarial Perturbation Defense (proves that perturbed synthetic telemetry is immediately repudiated).

---

## 4. Running the Verification Suite

To execute the complete verification campaign from the command line:

```bash
# Run all unit tests
make test

# Run the 16 formal acceptance gates and export certified evidence bundle
make acceptance

# Run the independent evidence auditor with 14 negative controls
make verify

# Run micro and macro performance benchmarks
make benchmark

# Run the zero em/en dash typography linter
make lint
```
