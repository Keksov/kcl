#!/bin/bash
# CopyTo.sh - Test string.copyTo method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Copy to (not implemented)
test_start "Copy to"
result=$(string.copyTo "test")
if [[ "$result" == "Not implemented" ]]; then
    test_pass "Copy to"
else
    test_fail "Copy to (expected: 'Not implemented', got: '$result')"
fi
