#!/bin/bash
# 020_integer_to_file_attributes.sh - Test TFile.IntegerToFileAttributes method
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Set up temp directory for this test


# Test 1: Convert 0 to attributes
kt_test_start "Convert 0 to attributes"
result=$(tfile.integerToFileAttributes 0)
if [[ "$result" == "[]" ]]; then
    kt_test_pass "Convert 0 to attributes"
else
    kt_test_fail "Convert 0 to attributes (expected: [], got: $result)"
fi

# Test 2: Convert positive integer to attributes
kt_test_start "Convert positive integer to attributes"
result=$(tfile.integerToFileAttributes 1)
if [[ -n "$result" ]]; then
    kt_test_pass "Convert positive integer to attributes"
else
    kt_test_fail "Convert positive integer to attributes"
fi
