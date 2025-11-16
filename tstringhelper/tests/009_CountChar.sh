#!/bin/bash
# CountChar.sh - Test string.countChar method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Count occurrences
test_start "Count char"
result=$(string.countChar "hello world" "l")
if [[ "$result" == "3" ]]; then
    test_pass "Count char"
else
    test_fail "Count char (expected: 3, got: '$result')"
fi

# Test 2: No occurrences
test_start "No occurrences"
result=$(string.countChar "hello" "z")
if [[ "$result" == "0" ]]; then
    test_pass "No occurrences"
else
    test_fail "No occurrences (expected: 0, got: '$result')"
fi
