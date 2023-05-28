#!/usr/bin/env Rscript
# Polaris Invariant Enforcement: Zero Em Dash Verifier
# Scans all source, test, doc, script, and config files for forbidden em/en dashes.

args <- commandArgs(trailingOnly = TRUE)
root_dir <- if (length(args) > 0) args[1] else "."

cat("[polaris-lint] Scanning repository for forbidden em/en dash characters...\n")

file_list <- list.files(
  path = root_dir,
  recursive = TRUE,
  full.names = TRUE,
  all.files = FALSE
)

# Exclude .git, compiled shared objects, and artifacts
file_list <- file_list[!grepl("/\\.git/", file_list)]
file_list <- file_list[!grepl("\\.(so|o|a|dylib|rda|rds|png|jpg|pdf)$", file_list)]
file_list <- file_list[!grepl("/artifacts/", file_list)]

violations <- list()

for (f in file_list) {
  if (!file.exists(f) || file.info(f)$isdir) next
  lines <- tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"), error = function(e) NULL)
  if (is.null(lines)) next
  
  for (idx in seq_along(lines)) {
    line <- lines[idx]
    # Check for Unicode em dash (\u2014) and en dash (\u2013)
    if (grepl("[\u2013\u2014]", line)) {
      violations[[length(violations) + 1]] <- list(
        file = f,
        line_num = idx,
        content = trimws(line)
      )
    }
  }
}

if (length(violations) > 0) {
  cat(sprintf("[FATAL] Found %d forbidden dash violation(s):\n", length(violations)))
  for (v in violations) {
    cat(sprintf("  %s:%d: %s\n", v$file, v$line_num, v$content))
  }
  quit(status = 1)
} else {
  cat(sprintf("[polaris-lint] Checked %d files: 0 em/en dash violations found. PASS.\n", length(file_list)))
  quit(status = 0)
}
