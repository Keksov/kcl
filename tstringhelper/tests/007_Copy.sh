#!/bin/bash
# Copy.sh - Test string.copy method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Copy string
test_start "Copy string"
result=$(string.copy "hello")
if [[ "$result" == "hello" ]]; then
    test_pass "Copy string"
else
    test_fail "Copy string (expected: 'hello', got: '$result')"
fi
