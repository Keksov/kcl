#!/bin/bash
# tests.sh - Run all TCustomApplication unit tests
# Auto-generated for kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

echo "Running TCustomApplication Unit Tests"
echo "====================================="

# Run individual test files
test_files=(
    "001_BasicCreationAndInitialization.sh"
    "002_TerminateOperations.sh"
    "003_ExceptionHandling.sh"
    "004_RunOperations.sh"
    "005_CommandLineOptions.sh"
    "006_GetNonOptions.sh"
    "007_EnvironmentAndLogging.sh"
    "008_PropertiesAndIntegration.sh"
    "009_OnExceptionProperty.sh"
    "010_EventLogFilter.sh"
    "011_ParamsIndices.sh"
    "012_GetNonOptionsProcedure.sh"
    "013_CheckOptionsTStrings.sh"
    "014_LogFiltering.sh"
    "015_TerminateExitCode.sh"
    "016_ExceptionIntegration.sh"
)

failed_tests=0
total_tests=0

for test_file in "${test_files[@]}"; do
    if [[ -f "$SCRIPT_DIR/$test_file" ]]; then
        echo "Running $test_file..."
        bash "$SCRIPT_DIR/$test_file" "$@"
        exit_code=$?
        ((total_tests++))
        if [[ $exit_code -ne 0 ]]; then
            ((failed_tests++))
            echo "FAILED: $test_file (exit code: $exit_code)"
        else
            echo "PASSED: $test_file"
        fi
        echo
    else
        echo "WARNING: Test file $test_file not found"
    fi
done

echo "====================================="
echo "Test Summary:"
echo "Total tests: $total_tests"
echo "Failed tests: $failed_tests"
echo "Passed tests: $((total_tests - failed_tests))"

if [[ $failed_tests -eq 0 ]]; then
    echo "All tests PASSED!"
    exit 0
else
    echo "Some tests FAILED!"
    exit 1
fi