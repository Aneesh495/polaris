# Polaris build and test automation Makefile
# Self-contained spatial-temporal graph routing engine

CC ?= clang
CFLAGS ?= -O3 -Wall -Wextra -pedantic -fPIC -std=c17
R_HOME ?= $(shell R RHOME 2>/dev/null || echo "/opt/homebrew/lib/R")
R_INCLUDES ?= $(shell R CMD config --cppflags 2>/dev/null || echo "-I/opt/homebrew/Cellar/r/4.5.1/lib/R/include")

.PHONY: all clean test test-unit test-integration test-regression verify benchmark lint serve doctor

all: src/polaris_accel.so

src/polaris_accel.so: src/polaris_accel.c src/polaris_accel.h
	@echo "==> Compiling native C acceleration kernel..."
	cd src && R CMD SHLIB polaris_accel.c -o polaris_accel.so

clean:
	@echo "==> Cleaning compiled artifacts..."
	rm -f src/*.o src/*.so src/*.dylib src/Makevars
	rm -rf artifacts tmp dist

test: all
	@echo "==> Running full test harness..."
	Rscript tests/test_runner.R --suite all

test-unit: all
	@echo "==> Running unit test suites..."
	Rscript tests/test_runner.R --suite unit

test-integration: all
	@echo "==> Running integration test suites..."
	Rscript tests/test_runner.R --suite integration

test-regression: all
	@echo "==> Running bug regression ledger tests..."
	Rscript tests/test_runner.R --suite regression

verify: all
	@echo "==> Executing 16 Acceptance Gates and certified evidence export..."
	Rscript tools/run_acceptance.R -o artifacts/evidence_bundle.json
	@echo "==> Auditing evidence bundle with 14 Negative Controls..."
	Rscript tools/verify_evidence.R artifacts/evidence_bundle.json --negative-controls

benchmark: all
	@echo "==> Executing computational benchmarks..."
	Rscript tools/run_benchmarks.R -o artifacts/benchmarks.json

lint:
	@echo "==> Verifying zero em dash invariant..."
	Rscript tools/lint_em_dashes.R

serve: all
	@echo "==> Launching Polaris HTTP/1.1 daemon server on port 8080..."
	./bin/polaris serve --port 8080

doctor:
	@echo "==> Polaris System Diagnostics..."
	./bin/polaris doctor
