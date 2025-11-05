#!/bin/bash
# ToBoolean.sh - Test string.toBoolean method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: True
test_start "To boolean true"
result=$(string.toBoolean "true")
if [[ "$result" == "true" ]]; then
    test_pass "To boolean true"
else
    test_fail "To boolean true (expected: true, got: '$result')"
fi

# Test 2: False
test_start "To boolean false"
result=$(string.toBoolean "false")
if [[ "$result" == "false" ]]; then
    test_pass "To boolean false"
else
    test_fail "To boolean false (expected: false, got: '$result')"
fi
