#!/bin/bash
# ToUpper.sh - Test string.toUpper method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Convert to uppercase
test_start "To upper case"
result=$(string.toUpper "hello world")
if [[ "$result" == "HELLO WORLD" ]]; then
    test_pass "To upper case"
else
    test_fail "To upper case (expected: 'HELLO WORLD', got: '$result')"
fi

# Test 2: Already uppercase
test_start "Already uppercase"
result=$(string.toUpper "HELLO")
if [[ "$result" == "HELLO" ]]; then
    test_pass "Already uppercase"
else
    test_fail "Already uppercase (expected: 'HELLO', got: '$result')"
fi

# Test 3: Mixed case
test_start "Mixed case"
result=$(string.toUpper "HeLLo WoRlD")
if [[ "$result" == "HELLO WORLD" ]]; then
    test_pass "Mixed case"
else
    test_fail "Mixed case (expected: 'HELLO WORLD', got: '$result')"
fi

# Test 4: Empty string
test_start "Empty string"
result=$(string.toUpper "")
if [[ "$result" == "" ]]; then
    test_pass "Empty string"
else
    test_fail "Empty string (expected: '', got: '$result')"
fi
