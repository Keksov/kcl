#!/bin/bash
# 020_integer_to_file_attributes.sh - Test TFile.IntegerToFileAttributes method
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Set up temp directory for this test


# Test 1: Convert 0 to attributes
kk_test_start "Convert 0 to attributes"
result=$(tfile.integerToFileAttributes 0)
if [[ "$result" == "[]" ]]; then
    kk_test_pass "Convert 0 to attributes"
else
    kk_test_fail "Convert 0 to attributes (expected: [], got: $result)"
fi

# Test 2: Convert positive integer to attributes
kk_test_start "Convert positive integer to attributes"
result=$(tfile.integerToFileAttributes 1)
if [[ -n "$result" ]]; then
    kk_test_pass "Convert positive integer to attributes"
else
    kk_test_fail "Convert positive integer to attributes"
fi
