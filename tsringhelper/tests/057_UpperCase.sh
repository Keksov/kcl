#!/bin/bash
# UpperCase.sh - Test string.upperCase method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Upper case
test_start "Upper case"
result=$(string.upperCase "hello")
if [[ "$result" == "HELLO" ]]; then
    test_pass "Upper case"
else
    test_fail "Upper case (expected: 'HELLO', got: '$result')"
fi
