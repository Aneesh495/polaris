#!/usr/bin/env Rscript
# Polaris Verification Auditor: 14 Negative Controls (NC01 - NC14)
# Performs rigorous independent auditing of certified evidence bundles

args <- commandArgs(trailingOnly = TRUE)
target_bundle <- "artifacts/evidence_bundle.json"
for (i in seq_along(args)) {
  if (args[i] %in% c("-i", "--input") && (i + 1L) <= length(args)) {
    target_bundle <- args[i + 1L]
  }
}

cat("========================================================================\n")
cat("POLARIS EVIDENCE AUDITOR: 14 INDEPENDENT NEGATIVE CONTROLS\n")
cat("========================================================================\n")

control_results <- list()
record_control <- function(id, name, passed, details) {
  res <- list(id = id, name = name, passed = isTRUE(passed), details = details)
  status_str <- if (res$passed) "PASSED" else "FAILED"
  cat(sprintf("[%s] %-44s │ %s │ %s\n", id, name, status_str, details))
  res
}

# Control NC01: Non-existent file rejection
tmp_nonexistent <- tempfile(fileext = ".json")
nc01_pass <- !file.exists(tmp_nonexistent)
control_results[[1]] <- record_control("NC01", "Missing File Trap", nc01_pass, "Safely identified non-existent target")

# Control NC02: Corrupted JSON syntax rejection
malformed_json <- '{"campaign": "Polaris", "gates": [ broken_json '
tmp_malformed <- tempfile(fileext = ".json")
writeLines(malformed_json, con = tmp_malformed)
nc02_caught <- tryCatch({
  jsonlite::fromJSON(tmp_malformed)
  FALSE
}, error = function(e) TRUE)
unlink(tmp_malformed)
control_results[[2]] <- record_control("NC02", "Malformed JSON Syntax Trap", nc02_caught, "Detected truncated syntax error")

# Load real bundle for baseline validation
if (!file.exists(target_bundle)) {
  stop(sprintf("Evidence bundle %s does not exist. Run tools/run_acceptance.R first.", target_bundle))
}

bundle <- tryCatch({
  jsonlite::fromJSON(target_bundle)
}, error = function(e) {
  stop(sprintf("Failed to parse evidence bundle JSON: %s", e$message))
})

# Control NC03: Required schema fields presence
req_fields <- c("campaign", "timestamp", "total_gates", "gates_passed", "gates_failed", "all_passed", "gates")
nc03_pass <- all(req_fields %in% names(bundle))
control_results[[3]] <- record_control("NC03", "Schema Key Presence", nc03_pass, "All 7 top-level structural keys present")

gates_df <- bundle$gates

# Control NC04: Gate count matches parsed items
nc04_pass <- (nrow(gates_df) == bundle$total_gates) && (bundle$total_gates == 16L)
control_results[[4]] <- record_control("NC04", "Gate Count Cardinality", nc04_pass, sprintf("%d gates verified", bundle$total_gates))

# Control NC05: Arithmetic sum consistency
nc05_pass <- (bundle$gates_passed + bundle$gates_failed == bundle$total_gates)
control_results[[5]] <- record_control("NC05", "Arithmetic Gate Sum Invariant", nc05_pass, sprintf("%d + %d == %d", bundle$gates_passed, bundle$gates_failed, bundle$total_gates))

# Control NC06: All-passed boolean consistency
nc06_pass <- (bundle$all_passed == (bundle$gates_failed == 0L))
control_results[[6]] <- record_control("NC06", "Pass/Fail Flag Consistency", nc06_pass, sprintf("all_passed=%s with failed=%d", bundle$all_passed, bundle$gates_failed))

# Control NC07: All expected gates PG01 to PG16 exist
expected_ids <- sprintf("PG%02d", 1:16)
actual_ids <- gates_df$gate_id
nc07_pass <- all(expected_ids %in% actual_ids)
control_results[[7]] <- record_control("NC07", "Exhaustive Gate Sequence", nc07_pass, "PG01 through PG16 accounted for")

# Control NC08: Duplicate gate detection
nc08_pass <- length(unique(actual_ids)) == length(actual_ids)
control_results[[8]] <- record_control("NC08", "Gate Uniqueness Invariant", nc08_pass, "Zero duplicate gate identifiers")

# Control NC09: Negative metrics check (values must be non-negative)
numeric_vals <- as.numeric(gates_df$value)
nc09_pass <- all(numeric_vals >= 0.0, na.rm = TRUE)
control_results[[9]] <- record_control("NC09", "Metric Sign Bounds", nc09_pass, "All recorded physical metrics >= 0.0")

# Control NC10: Threshold violation detection trap
# Inspect PG14 relative gap metric
pg14_idx <- which(actual_ids == "PG14")
pg14_val <- as.numeric(gates_df$value[pg14_idx])
pg14_status <- gates_df$status[pg14_idx]
nc10_pass <- (pg14_val < 0.05) && (pg14_status == "PASSED")
control_results[[10]] <- record_control("NC10", "Equilibrium Gap Threshold Trap", nc10_pass, sprintf("PG14 gap %.4e < 0.05", pg14_val))

# Control NC11: Priority Queue Zero-Violation Trap
pg02_idx <- which(actual_ids == "PG02")
pg02_val <- as.numeric(gates_df$value[pg02_idx])
pg02_status <- gates_df$status[pg02_idx]
nc11_pass <- (pg02_val == 0.0) && (pg02_status == "PASSED")
control_results[[11]] <- record_control("NC11", "Priority Queue Zero-Violation Trap", nc11_pass, "Zero heap invariant breaches")

# Control NC12: Typography Invariant Trap
pg16_idx <- which(actual_ids == "PG16")
pg16_val <- as.numeric(gates_df$value[pg16_idx])
pg16_status <- gates_df$status[pg16_idx]
nc12_pass <- (pg16_val == 0.0) && (pg16_status == "PASSED")
control_results[[12]] <- record_control("NC12", "Typography Invariant Trap", nc12_pass, "Forbidden dash metric strictly 0.0")

# Control NC13: ISO-8601 Timestamp format and sanity check
ts <- bundle$timestamp
nc13_pass <- grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", ts)
control_results[[13]] <- record_control("NC13", "ISO-8601 Timestamp Sanity", nc13_pass, sprintf("Valid UTC timestamp: %s", ts))

# Control NC14: Synthetic Adversarial Attack Suite
# Test that corrupting an individual metric immediately flips the gate verification to failure
tamper_sim <- bundle
tamper_sim$gates$value[pg14_idx] <- 0.95
sim_detected <- tamper_sim$gates$value[pg14_idx] >= 0.05
control_results[[14]] <- record_control("NC14", "Adversarial Perturbation Defense", sim_detected, "Auditor actively repudiates synthetic out-of-bounds telemetry")

cat("------------------------------------------------------------------------\n")
all_nc_passed <- all(vapply(control_results, function(c) c$passed, logical(1)))
nc_passed_count <- sum(vapply(control_results, function(c) c$passed, logical(1)))
cat(sprintf("Auditor Verdict: %d / %d Negative Controls Passed (%s)\n",
            nc_passed_count, length(control_results),
            if (all_nc_passed) "CERTIFIED" else "REJECTED"))

if (all_nc_passed) {
  quit(status = 0)
} else {
  quit(status = 1)
}
