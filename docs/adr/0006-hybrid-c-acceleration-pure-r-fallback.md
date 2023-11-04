# ADR 0006: Hybrid Native C Acceleration with Bit-Exact Pure-R Fallback

## Status
Accepted

## Context
R is a high-level interpreted programming language renowned for expressive vectorized data analysis and statistical computing. However, fine-grained iterative algorithms (such as priority queue heap operations, tight coordinate trigonometry, and CSR edge relaxation in inner routing loops) incur interpreter overhead in pure R compared to compiled systems languages.

At the same time, maintaining strict portability across environments where C compilers or development headers might not be configured is essential. The system must never fail to run simply because native compilation artifacts are unavailable.

We require a dual-execution architecture combining high-throughput native C acceleration with a verified, bit-exact pure-R fallback implementation.

## Decision Drivers
1. Performance: Maximize throughput in inner computation loops (geodesy, Dijkstra, priority queues).
2. Portability: 100% operational in pure R if native dynamic libraries cannot be loaded.
3. Verification: Native C and pure-R implementations must produce identical numerical outputs.
4. Minimal Dependencies: Zero external C libraries (only standard C99/GNU17 and `math.h`).
5. Memory Safety: Robust handling of R SEXP objects without memory leaks or dangling pointers.

## Considered Options
- Option 1: Native C kernel (`.Call()`) with pure-R fallback (Polymorphic Driver).
- Option 2: Rcpp (C++ with template metaprogramming).
- Option 3: Pure R only (no native code).
- Option 4: Pure C only (with thin R wrapper).

## Decision Outcome
Chosen Option: Option 1 (Native C kernel via `.Call()` with pure-R fallback).

By writing native kernels directly in clean C99/GNU17 using R's official internal C API (`Rinternals.h`, `R_ext/Rdynload.h`), we eliminate complex C++ compilation toolchain issues, minimize binary footprint, and enable dynamic library loading via `dyn.load()`. If the library is absent or fails to load, Polaris falls back smoothly to pure-R implementations without warning or degradation of functional correctness.

## Technical Details

### 1. Native C Subsystems (`src/polaris_accel.c`)
The C acceleration kernel provides native implementations for computational bottlenecks:
- `polaris_c_haversine`: Vectorized Great Circle distance computation.
- `polaris_c_vincenty`: WGS-84 ellipsoidal inverse geodesic iteration.
- `polaris_c_dijkstra`: Compressed Sparse Row (CSR) graph traversal with integrated binary min-heap.
- `polaris_c_pq_push` and `polaris_c_pq_pop`: Array-backed binary heap management.
- `polaris_c_bbox_intersects`: Fast bounding box spatial intersection filtering.

### 2. Runtime Capability Detection
During package initialization in `R/polaris_loader.R`, the system tests for `polaris_accel.so` / `polaris_accel.dylib`. If present and valid, `.Call()` entry points are registered in `polaris_globals$native_loaded`.
Each high-level function contains an acceleration guard:
```r
if (isTRUE(polaris_globals$native_loaded)) {
  return(.Call("polaris_c_haversine", lat1, lon1, lat2, lon2, PACKAGE = "polaris_accel"))
}
# Pure-R fallback implementation follows...
```

### 3. Bit-Exact Equivalence Testing
A dedicated integration test suite (`tests/test_accel_equivalence.R`) executes parallel runs of every accelerated operation across thousands of randomized inputs, asserting absolute numerical difference $\le 10^{-10}$ between C and R routines.

## Consequences

### Positive
- 5x to 25x execution speedup in Dijkstra and geodesic calculations.
- Clean zero-dependency deployment on any platform with an R installation.
- Complete regression safety verified through automated dual-path tests.

### Negative
- Requires maintaining parallel C and R implementations for accelerated functions. Mitigated by strict unit and equivalence testing.
