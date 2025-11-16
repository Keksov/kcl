#!/bin/bash
# TrimLeft.sh - Test string.trimLeft method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Trim left
test_start "Trim left"
result=$(string.trimLeft "  hello")
if [[ "$result" == "hello" ]]; then
    test_pass "Trim left"
else
    test_fail "Trim left (expected: 'hello', got: '$result')"
fi
