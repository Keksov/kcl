#!/bin/bash
# ToUpperInvariant.sh - Test string.toUpperInvariant method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: To upper invariant
test_start "To upper invariant"
result=$(string.toUpperInvariant "hello")
if [[ "$result" == "HELLO" ]]; then
    test_pass "To upper invariant"
else
    test_fail "To upper invariant (expected: 'HELLO', got: '$result')"
fi
