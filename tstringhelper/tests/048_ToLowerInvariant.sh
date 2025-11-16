#!/bin/bash
# ToLowerInvariant.sh - Test string.toLowerInvariant method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: To lower invariant
test_start "To lower invariant"
result=$(string.toLowerInvariant "HELLO")
if [[ "$result" == "hello" ]]; then
    test_pass "To lower invariant"
else
    test_fail "To lower invariant (expected: 'hello', got: '$result')"
fi
