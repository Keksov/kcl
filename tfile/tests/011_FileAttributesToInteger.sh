#!/bin/bash
# 011_file_attributes_to_integer.sh - Test TFile.FileAttributesToInteger method
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


# Test 1: Convert empty attributes
kt_test_start "Convert empty attributes"
result=$(tfile.fileAttributesToInteger "[]")
if [[ $result -eq 0 ]]; then
    kt_test_pass "Convert empty attributes"
else
    kt_test_fail "Convert empty attributes (expected: 0, got: $result)"
fi

# Test 2: Convert single attribute
kt_test_start "Convert single attribute"
result=$(tfile.fileAttributesToInteger "[ReadOnly]")
if [[ $result -gt 0 ]]; then
    kt_test_pass "Convert single attribute"
else
    kt_test_fail "Convert single attribute"
fi

# Test 3: Convert multiple attributes
kt_test_start "Convert multiple attributes"
result=$(tfile.fileAttributesToInteger "[ReadOnly, Hidden]")
if [[ $result -gt 0 ]]; then
    kt_test_pass "Convert multiple attributes"
else
    kt_test_fail "Convert multiple attributes"
fi
