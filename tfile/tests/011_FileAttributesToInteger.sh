#!/bin/bash
# 011_file_attributes_to_integer.sh - Test TFile.FileAttributesToInteger method
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


# Test 1: Convert empty attributes
kk_test_start "Convert empty attributes"
result=$(tfile.fileAttributesToInteger "[]")
if [[ $result -eq 0 ]]; then
    kk_test_pass "Convert empty attributes"
else
    kk_test_fail "Convert empty attributes (expected: 0, got: $result)"
fi

# Test 2: Convert single attribute
kk_test_start "Convert single attribute"
result=$(tfile.fileAttributesToInteger "[ReadOnly]")
if [[ $result -gt 0 ]]; then
    kk_test_pass "Convert single attribute"
else
    kk_test_fail "Convert single attribute"
fi

# Test 3: Convert multiple attributes
kk_test_start "Convert multiple attributes"
result=$(tfile.fileAttributesToInteger "[ReadOnly, Hidden]")
if [[ $result -gt 0 ]]; then
    kk_test_pass "Convert multiple attributes"
else
    kk_test_fail "Convert multiple attributes"
fi
