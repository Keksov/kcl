#!/bin/bash
# CompareText.sh - Test string.compareText method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Case insensitive equal
test_start "CompareText equal ignore case"
result=$(string.compareText "Hello" "HELLO")
if [[ "$result" == "0" ]]; then
    test_pass "CompareText equal ignore case"
else
    test_fail "CompareText equal ignore case (expected: 0, got: '$result')"
fi

# Test 2: Different case
test_start "CompareText different"
result=$(string.compareText "abc" "DEF")
if [[ "$result" == "-1" ]]; then
    test_pass "CompareText different"
else
    test_fail "CompareText different (expected: -1, got: '$result')"
fi
