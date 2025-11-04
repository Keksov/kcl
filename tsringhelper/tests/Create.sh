#!/bin/bash
# Create.sh - Test string.create method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Create string
test_start "Create string"
result=$(string.create "*" 5)
if [[ "$result" == "*****" ]]; then
    test_pass "Create string"
else
    test_fail "Create string (expected: '*****', got: '$result')"
fi
