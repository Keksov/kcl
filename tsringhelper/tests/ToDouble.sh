#!/bin/bash
# ToDouble.sh - Test string.toDouble method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Convert to double
test_start "To double"
result=$(string.toDouble "3.14")
if [[ "$result" == "3.14" ]]; then
    test_pass "To double"
else
    test_fail "To double (expected: 3.14, got: '$result')"
fi
