#!/bin/bash
# ToInt64.sh - Test string.toInt64 method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Convert to int
test_start "To int64"
result=$(string.toInt64 "42")
if [[ "$result" == "42" ]]; then
    test_pass "To int64"
else
    test_fail "To int64 (expected: 42, got: '$result')"
fi
