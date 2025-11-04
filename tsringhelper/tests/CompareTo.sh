#!/bin/bash
# CompareTo.sh - Test string.compareTo method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Equal
test_start "CompareTo equal"
result=$(string.compareTo "test" "test")
if [[ "$result" == "0" ]]; then
    test_pass "CompareTo equal"
else
    test_fail "CompareTo equal (expected: 0, got: '$result')"
fi

# Test 2: Less
test_start "CompareTo less"
result=$(string.compareTo "abc" "def")
if [[ "$result" == "-1" ]]; then
    test_pass "CompareTo less"
else
    test_fail "CompareTo less (expected: -1, got: '$result')"
fi
