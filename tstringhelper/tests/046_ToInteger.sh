#!/bin/bash
# ToInteger.sh - Test string.toInteger method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Convert to int
test_start "To integer"
result=$(string.toInteger "123")
if [[ "$result" == "123" ]]; then
    test_pass "To integer"
else
    test_fail "To integer (expected: 123, got: '$result')"
fi
