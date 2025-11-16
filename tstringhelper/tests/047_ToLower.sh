#!/bin/bash
# ToLower.sh - Test string.toLower method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Convert to lowercase
test_start "To lower case"
result=$(string.toLower "HELLO WORLD")
if [[ "$result" == "hello world" ]]; then
    test_pass "To lower case"
else
    test_fail "To lower case (expected: 'hello world', got: '$result')"
fi

# Test 2: Already lowercase
test_start "Already lowercase"
result=$(string.toLower "hello")
if [[ "$result" == "hello" ]]; then
    test_pass "Already lowercase"
else
    test_fail "Already lowercase (expected: 'hello', got: '$result')"
fi

# Test 3: Mixed case
test_start "Mixed case"
result=$(string.toLower "HeLLo WoRlD")
if [[ "$result" == "hello world" ]]; then
    test_pass "Mixed case"
else
    test_fail "Mixed case (expected: 'hello world', got: '$result')"
fi

# Test 4: Empty string
test_start "Empty string"
result=$(string.toLower "")
if [[ "$result" == "" ]]; then
    test_pass "Empty string"
else
    test_fail "Empty string (expected: '', got: '$result')"
fi
