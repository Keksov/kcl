#!/bin/bash
# 011_file_attributes_to_integer.sh - Test TFile.FileAttributesToInteger method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "011"


# Test 1: Convert empty attributes
test_start "Convert empty attributes"
result=$(tfile.fileAttributesToInteger "[]")
if [[ $result -eq 0 ]]; then
    test_pass "Convert empty attributes"
else
    test_fail "Convert empty attributes (expected: 0, got: $result)"
fi

# Test 2: Convert single attribute
test_start "Convert single attribute"
result=$(tfile.fileAttributesToInteger "[ReadOnly]")
if [[ $result -gt 0 ]]; then
    test_pass "Convert single attribute"
else
    test_fail "Convert single attribute"
fi

# Test 3: Convert multiple attributes
test_start "Convert multiple attributes"
result=$(tfile.fileAttributesToInteger "[ReadOnly, Hidden]")
if [[ $result -gt 0 ]]; then
    test_pass "Convert multiple attributes"
else
    test_fail "Convert multiple attributes"
fi
