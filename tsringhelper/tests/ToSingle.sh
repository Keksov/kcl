#!/bin/bash
# ToSingle.sh - Test string.toSingle method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: To single
test_start "To single"
result=$(string.toSingle "2.5")
if [[ "$result" == "2.5" ]]; then
    test_pass "To single"
else
    test_fail "To single (expected: 2.5, got: '$result')"
fi
