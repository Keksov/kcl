#!/bin/bash
# DeQuotedString.sh - Test string.deQuotedString method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Remove quotes
test_start "Dequote string"
result=$(string.deQuotedString "\"hello\"")
if [[ "$result" == "hello" ]]; then
    test_pass "Dequote string"
else
    test_fail "Dequote string (expected: 'hello', got: '$result')"
fi
