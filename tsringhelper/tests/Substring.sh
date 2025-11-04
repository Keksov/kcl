#!/bin/bash
# Substring.sh - Test string.substring method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Substring from index
test_start "Substring from index"
result=$(string.substring "hello world" 6)
if [[ "$result" == "world" ]]; then
    test_pass "Substring from index"
else
    test_fail "Substring from index (expected: 'world', got: '$result')"
fi

# Test 2: Substring with length
test_start "Substring with length"
result=$(string.substring "hello world" 0 5)
if [[ "$result" == "hello" ]]; then
    test_pass "Substring with length"
else
    test_fail "Substring with length (expected: 'hello', got: '$result')"
fi

# Test 3: Substring beyond length
test_start "Substring beyond length"
result=$(string.substring "hello" 3 10)
if [[ "$result" == "lo" ]]; then
    test_pass "Substring beyond length"
else
    test_fail "Substring beyond length (expected: 'lo', got: '$result')"
fi

# Test 4: Start index 0
test_start "Start index 0"
result=$(string.substring "hello" 0)
if [[ "$result" == "hello" ]]; then
    test_pass "Start index 0"
else
    test_fail "Start index 0 (expected: 'hello', got: '$result')"
fi

# Test 5: Empty string
test_start "Empty string substring"
result=$(string.substring "" 0)
if [[ "$result" == "" ]]; then
    test_pass "Empty string substring"
else
    test_fail "Empty string substring (expected: '', got: '$result')"
fi
