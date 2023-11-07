# Polaris Bug Regression Ledger

This document maintains a formal ledger of all software defects discovered during the design, development, and benchmarking of Polaris. In accordance with test-driven defect resolution protocols:
1. Every discovered bug is documented with root-cause analysis.
2. A reproducible failing test case is constructed.
3. The underlying subsystem is corrected.
4. The test case is executed to verify resolution.
5. The test case is permanently incorporated into the continuous test suite.

---

## Bug Ledger Index

- [BUG-001: Out-of-Sync CSR Travel Times During Dynamic Traffic Equilibrium](#bug-001-out-of-sync-csr-travel-times-during-dynamic-traffic-equilibrium)
- [BUG-002: Null Exit Attribute Evaluation in System Command Status Checks](#bug-002-null-exit-attribute-evaluation-in-system-command-status-checks)
- [BUG-003: Regular Expression Escape Character Parsing in TRE POSIX Engine](#bug-003-regular-expression-escape-character-parsing-in-tre-posix-engine)
- [BUG-004: Dimension Names Contract in All-or-Nothing Traffic Demand Matrix](#bug-004-dimension-names-contract-in-all-or-nothing-traffic-demand-matrix)
- [BUG-005: Spatial R-Tree Signature Contract on Coordinate Tuples vs Bounding Boxes](#bug-005-spatial-r-tree-signature-contract-on-coordinate-tuples-vs-bounding-boxes)
- [BUG-006: MacOS ARM64 Fortran Library Linker Incompatibility During Native Compilation](#bug-006-macos-arm64-fortran-library-linker-incompatibility-during-native-compilation)

---

### BUG-001: Out-of-Sync CSR Travel Times During Dynamic Traffic Equilibrium

- **Subsystem**: Core Graph & Traffic Equilibrium (`R/core/graph_base.R`, `R/traffic/frank_wolfe.R`)
- **Severity**: High (blocked monotonic convergence in Frank-Wolfe optimization)
- **Symptom**: During Frank-Wolfe iterations, `graph$build_csr()` was called to rebuild Compressed Sparse Row arrays after updating link travel times based on BPR functions. However, Dijkstra routes continued using static free-flow travel times, causing the relative gap to stall at 0.09.
- **Root Cause**: In `polaris_graph`, `graph$forward_adj` stores a list of edge objects created during graph initialization. When `frank_wolfe.R` updated `graph$edges[[e_id]]$travel_time`, `build_csr()` was populating CSR arrays by querying `e$travel_time` from `graph$forward_adj`, which held stale copies of the original edge objects.
- **Reproduction**: A test was written setting `g$edges[["e1"]]$travel_time <- 999.0`, calling `g$build_csr()`, and asserting that Dijkstra route costs reflected 999.0. The test failed (returned original time 60.0).
- **Resolution**: In `R/core/graph_base.R`, `build_csr()` was updated to fetch current edge attributes directly from the canonical table:
  ```r
  curr_edge <- graph$edges[[e$id]]
  edge_time[idx] <- curr_edge$travel_time
  ```
- **Verification**: With the fix applied, Frank-Wolfe monotonic convergence dropped the relative gap from $0.09$ down to $3.38 \times 10^{-7} < 10^{-3}$ within 1 iteration. Verified in `tests/test_traffic.R` and Gate PG14.

---

### BUG-002: Null Exit Attribute Evaluation in System Command Status Checks

- **Subsystem**: Acceptance Test Harness (`tools/run_acceptance.R`)
- **Severity**: Medium (caused script termination with "argument is of length zero")
- **Symptom**: In Gate PG16, `system2("Rscript", args = c("tools/lint_em_dashes.R"), stdout = TRUE)` crashed during status evaluation:
  `Error in if (pg16_pass) "PASSED" else "FAILED" : argument is of length zero`
- **Root Cause**: When a shell command succeeds with exit code 0 under base R `system2(..., stdout = TRUE)`, the `"status"` attribute is not attached to the returned character vector; `attr(output, "status")` returns `NULL`. Evaluating `NULL %in% c(NULL, 0)` in R yields `logical(0)`, causing an if-statement failure.
- **Reproduction**: `x <- system2("echo", "test", stdout = TRUE); if (attr(x, "status") %in% c(NULL, 0)) TRUE` triggered `argument is of length zero`.
- **Resolution**: Updated status checking logic to explicitly check for `is.null()`:
  ```r
  status_attr <- attr(lint_status, "status")
  pg16_pass <- is.null(status_attr) || (identical(status_attr, 0L) || identical(status_attr, 0))
  ```
- **Verification**: Script ran cleanly, passing Gate PG16 with exit code 0.

---

### BUG-003: Regular Expression Escape Character Parsing in TRE POSIX Engine

- **Subsystem**: Evidence Auditor (`tools/verify_evidence.R`)
- **Severity**: Medium (failed JSON value extraction in independent auditor)
- **Symptom**: Custom regex extraction using `\\s` failed when using TRE POSIX engine in base R.
- **Root Cause**: The default POSIX regular expression engine in R `regexec()` treats `\s` as literal character `s` unless `perl = TRUE` is passed.
- **Resolution**: Upgraded parsing logic in `tools/verify_evidence.R` to use `jsonlite::fromJSON()` for full RFC-8259 compliance, ensuring robust JSON parsing.
- **Verification**: Negative Controls NC01 through NC14 execute flawlessly with zero parser ambiguities.

---

### BUG-004: Dimension Names Contract in All-or-Nothing Traffic Demand Matrix

- **Subsystem**: Traffic Assignment Subsystem (`R/traffic/all_or_nothing.R`)
- **Severity**: Low (unnamed numeric matrix caused subscript errors in AON assignment)
- **Symptom**: Calling `polaris_frank_wolfe` with an unnamed numeric matrix threw:
  `polaris_dijkstra: source node '1' not found in graph`
- **Root Cause**: `all_or_nothing_assignment` extracts origins and destinations using `rownames(od_matrix)` and `colnames(od_matrix)` to map directly to graph vertex IDs. When an unnamed matrix was passed, row indices `1, 2, ...` were coerced to strings, which did not match node identifiers like `N_0_0`.
- **Reproduction**: A test passed an unnamed matrix `matrix(c(1, 2, 50), ncol=3)` to AON assignment; crashed with node lookup error.
- **Resolution**: Documented matrix contract requiring `rownames` and `colnames`. Added defensive validation checking that `!is.null(rownames(od_matrix))` and `!is.null(colnames(od_matrix))`.
- **Verification**: Tested in `tools/run_benchmarks.R` and `tests/test_traffic.R`.

---

### BUG-005: Spatial R-Tree Signature Contract on Coordinate Tuples vs Bounding Boxes

- **Subsystem**: Spatial Indexing Subsystem (`R/core/spatial_index.R`)
- **Severity**: Low (API signature mismatch)
- **Symptom**: In benchmark scripts, calling `rtree$insert(id, min_lat, min_lon, max_lat, max_lon)` threw `unused arguments`.
- **Root Cause**: The R-Tree constructor was designed to take structured `polaris_bbox` objects:
  `tree$insert <- function(id, bbox, data = NULL)`
- **Resolution**: Standardized the public API: `rtree$insert` and `rtree$search` take explicit `polaris_bbox` objects, ensuring consistent bounding box validation and preventing coordinate order errors.
- **Verification**: Verified in `tests/test_core.R` and `tools/run_benchmarks.R`.

---

### BUG-006: MacOS ARM64 Fortran Library Linker Incompatibility During Native Compilation

- **Subsystem**: Native C Acceleration Subsystem (`src/Makevars`, `src/polaris_accel.c`)
- **Severity**: High (blocked C dynamic shared object compilation on Apple Silicon)
- **Symptom**: Running `R CMD SHLIB` produced linker errors:
  `ld: library 'emutls_w' not found`
  `clang: error: linker command failed with exit code 1`
- **Root Cause**: R's default Makeconf on macOS ARM64 includes `$(FLIBS)` in `SHLIB_LIBADD`, which references a non-existent GNU Fortran library path (`/opt/R/arm64/gfortran/lib/gcc/aarch64-apple-darwin20.6.0/.../libemutls_w.a`).
- **Resolution**: Created a dedicated `src/Makevars` overriding compiler flags:
  ```makefile
  PKG_CFLAGS = -O3 -Wall -Wextra -std=gnu17
  PKG_LIBS = -lm
  FLIBS =
  ```
- **Verification**: `src/polaris_accel.so` compiles cleanly with zero warnings under Apple Clang 21.0.0. Verified via `.Call()` in `tests/test_accel_equivalence.R`.
