#!/bin/bash
# CompareOrdinal.sh - Test string.compareOrdinal method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Equal strings
test_start "CompareOrdinal equal"
result=$(string.compareOrdinal "abc" "abc")
if [[ "$result" == "0" ]]; then
    test_pass "CompareOrdinal equal"
else
    test_fail "CompareOrdinal equal (expected: 0, got: '$result')"
fi

# Test 2: Different strings
test_start "CompareOrdinal different"
result=$(string.compareOrdinal "abc" "def")
if [[ "$result" == "-1" ]]; then
    test_pass "CompareOrdinal different"
else
    test_fail "CompareOrdinal different (expected: -1, got: '$result')"
fi
