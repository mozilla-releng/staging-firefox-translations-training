#!/bin/bash
set -e

# Run script from the context of inference directory
cd "$(dirname $0)/.."

# Ensure script is running within docker
./scripts/detect-docker.sh inference-test

# Check if build-local/src/tests/units directory exists
if [ ! -d "build-local/src/tests/units" ]; then
    echo "Directory build-local/src/tests/units does not exist. Running build."
    ./scripts/build-local.sh --test
else
    echo "Directory build-local/src/tests/units already exists. Skipping build."
fi

# Change to the unit tests directory
cd build-local/src/tests/units

# List of test commands
tests=(
    "./run_annotation_tests"
    "./run_cache_tests"
    "./run_html_tests"
    "./run_quality_estimator_tests"
    "./run_xh_scanner_tests"
)

# Run all tests, collect failures
failures=0

for test in "${tests[@]}"; do
    echo "Running $test..."
    if ! $test; then
        echo "$test failed!"
        failures=$((failures + 1))
    fi
done

# If any test failed, exit with a non-zero status
if [ $failures -gt 0 ]; then
    echo "$failures test(s) failed."
    exit 1
else
    echo "All tests passed successfully."
    exit 0
fi
