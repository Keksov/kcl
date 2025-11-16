#!/bin/bash
# ToCharArray.sh - Test string.toCharArray method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: To char array
test_start "To char array"
result=$(string.toCharArray "hi")
# Expected output not defined, just check it runs
if [[ -n "$result" ]]; then
    test_pass "To char array"
else
    test_fail "To char array"
fi
