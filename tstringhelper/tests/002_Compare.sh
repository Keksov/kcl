#!/bin/bash
# Compare.sh - Test string.compare method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Equal strings
test_start "Compare equal strings"
result=$(string.compare "hello" "hello")
if [[ "$result" == "0" ]]; then
    test_pass "Compare equal strings"
else
    test_fail "Compare equal strings (expected: 0, got: '$result')"
fi

# Test 2: First string less than second
test_start "Compare strA < strB"
result=$(string.compare "apple" "banana")
if [[ "$result" == "-1" ]]; then
    test_pass "Compare strA < strB"
else
    test_fail "Compare strA < strB (expected: -1, got: '$result')"
fi

# Test 3: First string greater than second
test_start "Compare strA > strB"
result=$(string.compare "zebra" "apple")
if [[ "$result" == "1" ]]; then
    test_pass "Compare strA > strB"
else
    test_fail "Compare strA > strB (expected: 1, got: '$result')"
fi

# Test 4: Empty strings
test_start "Compare empty strings"
result=$(string.compare "" "")
if [[ "$result" == "0" ]]; then
    test_pass "Compare empty strings"
else
    test_fail "Compare empty strings (expected: 0, got: '$result')"
fi

# Test 5: One empty string
test_start "Compare empty and non-empty"
result=$(string.compare "" "test")
if [[ "$result" == "-1" ]]; then
    test_pass "Compare empty and non-empty"
else
    test_fail "Compare empty and non-empty (expected: -1, got: '$result')"
fi
