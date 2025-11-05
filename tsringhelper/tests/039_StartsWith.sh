#!/bin/bash
# StartsWith.sh - Test string.startsWith method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Starts with
test_start "Starts with"
result=$(string.startsWith "hello world" "hello")
if [[ "$result" == "true" ]]; then
    test_pass "Starts with"
else
    test_fail "Starts with (expected: true, got: '$result')"
fi

# Test 2: Does not start with
test_start "Does not start with"
result=$(string.startsWith "hello world" "world")
if [[ "$result" == "false" ]]; then
    test_pass "Does not start with"
else
    test_fail "Does not start with (expected: false, got: '$result')"
fi
