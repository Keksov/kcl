#!/bin/bash
# Length.sh - Test string.length property

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Length of non-empty string
test_start "Length of string"
result=$(string.length "hello")
if [[ "$result" == "5" ]]; then
    test_pass "Length of string"
else
    test_fail "Length of string (expected: 5, got: '$result')"
fi

# Test 2: Length of empty string
test_start "Length of empty string"
result=$(string.length "")
if [[ "$result" == "0" ]]; then
    test_pass "Length of empty string"
else
    test_fail "Length of empty string (expected: 0, got: '$result')"
fi

# Test 3: Length with spaces
test_start "Length with spaces"
result=$(string.length "hello world")
if [[ "$result" == "11" ]]; then
    test_pass "Length with spaces"
else
    test_fail "Length with spaces (expected: 11, got: '$result')"
fi
