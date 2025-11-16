#!/bin/bash
# TrimRight.sh - Test string.trimRight method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Trim right
test_start "Trim right"
result=$(string.trimRight "hello  ")
if [[ "$result" == "hello" ]]; then
    test_pass "Trim right"
else
    test_fail "Trim right (expected: 'hello', got: '$result')"
fi
