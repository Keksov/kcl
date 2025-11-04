#!/bin/bash
# Chars.sh - Test string.chars property

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Get char at index
test_start "Get char at index"
result=$(string.chars "hello" 0)
if [[ "$result" == "h" ]]; then
    test_pass "Get char at index"
else
    test_fail "Get char at index (expected: 'h', got: '$result')"
fi

# Test 2: Invalid index
test_start "Invalid index"
result=$(string.chars "hello" 10)
if [[ "$result" == "undefined" ]]; then
    test_pass "Invalid index"
else
    test_fail "Invalid index (expected: 'undefined', got: '$result')"
fi
