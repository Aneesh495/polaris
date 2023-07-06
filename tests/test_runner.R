#!/usr/bin/env Rscript
# Polaris Test Harness: TAP-13 Compliant Pure-R Test Runner
# Executes unit, integration, and regression test suites with zero external dependencies

# Locate project root
args <- commandArgs(trailingOnly = TRUE)
suite_filter <- "all"
for (i in seq_along(args)) {
  if (args[i] == "--suite" && i < length(args)) {
    suite_filter <- args[i + 1]
  }
}

project_root <- normalizePath(file.path(getwd()))
source(file.path(project_root, "R", "polaris_loader.R"))
polaris_load_all(project_root)

# Test assertion helpers
assert_true <- function(cond, message = "Assertion failed") {
  if (!isTRUE(cond)) {
    stop(sprintf("FAIL: %s (expected TRUE, got FALSE)", message), call. = FALSE)
  }
}

assert_equal <- function(actual, expected, message = "Equality failed", tol = 1e-7) {
  if (is.numeric(actual) && is.numeric(expected)) {
    diff_val <- max(abs(actual - expected))
    if (diff_val > tol) {
      stop(sprintf("FAIL: %s (diff %.6e > tol %.6e; actual=%s, expected=%s)",
                   message, diff_val, tol, paste(actual, collapse=","), paste(expected, collapse=",")), call. = FALSE)
    }
  } else {
    if (!identical(actual, expected)) {
      stop(sprintf("FAIL: %s (actual != expected)", message), call. = FALSE)
    }
  }
}

# Collect test files
test_dirs <- character(0)
if (suite_filter %in% c("all", "unit")) {
  test_dirs <- c(test_dirs, file.path(project_root, "tests", "unit"))
}
if (suite_filter %in% c("all", "integration")) {
  test_dirs <- c(test_dirs, file.path(project_root, "tests", "integration"))
}
if (suite_filter %in% c("all", "regression")) {
  test_dirs <- c(test_dirs, file.path(project_root, "tests", "regression"))
}

test_files <- character(0)
for (td in test_dirs) {
  if (dir.exists(td)) {
    test_files <- c(test_files, list.files(td, pattern = "^test_.*\\.R$", full.names = TRUE))
  }
}

cat("======================================================================\n")
cat(sprintf("Polaris Test Suite Execution: Filter = '%s' (%d test files)\n", suite_filter, length(test_files)))
cat("======================================================================\n")

total_tests <- 0L
passed_tests <- 0L
failed_tests <- 0L
failures <- list()

t0 <- proc.time()

for (tf in test_files) {
  test_name <- basename(tf)
  cat(sprintf("[RUN] %-40s ... ", test_name))
  flush.console()

  test_env <- new.env(parent = globalenv())
  test_env$assert_true <- assert_true
  test_env$assert_equal <- assert_equal

  res <- tryCatch({
    sys.source(tf, envir = test_env)
    TRUE
  }, error = function(e) {
    e$message
  })

  total_tests <- total_tests + 1L
  if (isTRUE(res)) {
    passed_tests <- passed_tests + 1L
    cat("PASS\n")
  } else {
    failed_tests <- failed_tests + 1L
    cat("FAIL\n")
    failures[[length(failures) + 1L]] <- list(file = test_name, error = res)
  }
}

elapsed <- (proc.time() - t0)["elapsed"]

cat("----------------------------------------------------------------------\n")
cat(sprintf("Test Summary: %d Total | %d Passed | %d Failed | Elapsed: %.3fs\n",
            total_tests, passed_tests, failed_tests, elapsed))

if (failed_tests > 0L) {
  cat("\nFailure Details:\n")
  for (f in failures) {
    cat(sprintf("  [%s]: %s\n", f$file, f$error))
  }
  cat("======================================================================\n")
  quit(status = 1)
} else {
  cat("All tests completed successfully. (100% PASS)\n")
  cat("======================================================================\n")
  quit(status = 0)
}
