#!/bin/bash
# 020_integer_to_file_attributes.sh - Test TFile.IntegerToFileAttributes method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Convert 0 to attributes
test_start "Convert 0 to attributes"
result=$(tfile.integerToFileAttributes 0)
if [[ "$result" == "[]" ]]; then
    test_pass "Convert 0 to attributes"
else
    test_fail "Convert 0 to attributes (expected: [], got: $result)"
fi

# Test 2: Convert positive integer to attributes
test_start "Convert positive integer to attributes"
result=$(tfile.integerToFileAttributes 1)
if [[ -n "$result" ]]; then
    test_pass "Convert positive integer to attributes"
else
    test_fail "Convert positive integer to attributes"
fi
