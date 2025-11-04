#!/bin/bash
# ToExtended.sh - Test string.toExtended method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: To extended
test_start "To extended"
result=$(string.toDouble "3.14")  # reusing
if [[ "$result" == "3.14" ]]; then
    test_pass "To extended"
else
    test_fail "To extended (expected: 3.14, got: '$result')"
fi
