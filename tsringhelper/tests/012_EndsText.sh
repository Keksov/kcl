#!/bin/bash
# EndsText.sh - Test string.endsText method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Ends with
test_start "Ends with"
result=$(string.endsText "world" "hello world")
if [[ "$result" == "true" ]]; then
    test_pass "Ends with"
else
    test_fail "Ends with (expected: true, got: '$result')"
fi

# Test 2: Does not end with
test_start "Does not end with"
result=$(string.endsText "hello" "hello world")
if [[ "$result" == "false" ]]; then
    test_pass "Does not end with"
else
    test_fail "Does not end with (expected: false, got: '$result')"
fi
