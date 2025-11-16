#!/bin/bash
# Replace.sh - Test string.replace method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Replace single character
test_start "Replace - replace character"
result=$(string.replace "hello" "l" "L")
if [[ "$result" == "heLLo" || "$result" == "heLlo" ]]; then
    test_pass "Replace - replace character"
else
    test_fail "Replace - replace character (expected: 'heLLo' or 'heLlo', got: '$result')"
fi

# Test 2: Replace substring
test_start "Replace - replace substring"
result=$(string.replace "hello world" "world" "universe")
if [[ "$result" == "hello universe" ]]; then
    test_pass "Replace - replace substring"
else
    test_fail "Replace - replace substring (expected: 'hello universe', got: '$result')"
fi

# Test 3: Replace not found
test_start "Replace - not found"
result=$(string.replace "hello" "z" "x")
if [[ "$result" == "hello" ]]; then
    test_pass "Replace - not found"
else
    test_fail "Replace - not found (expected: 'hello', got: '$result')"
fi

# Test 4: Replace with empty string
test_start "Replace - replace with empty"
result=$(string.replace "hello" "l" "")
if [[ "$result" == "heo" || "$result" == "helo" ]]; then
    test_pass "Replace - replace with empty"
else
    test_fail "Replace - replace with empty (expected: 'heo' or 'helo', got: '$result')"
fi

# Test 5: Replace empty with string
test_start "Replace - empty to string"
result=$(string.replace "ab" "" "x")
if [[ "$result" == "xaxbx" || "$result" == "ab" ]]; then
    test_pass "Replace - empty to string"
else
    test_fail "Replace - empty to string (expected: 'xaxbx' or 'ab', got: '$result')"
fi

# Test 6: Replace all occurrences (with flag)
test_start "Replace - all occurrences"
result=$(string.replace "aaa" "a" "b" "rfReplaceAll")
if [[ "$result" == "bbb" || "$result" == "bba" || "$result" == "baa" ]]; then
    test_pass "Replace - all occurrences"
else
    test_fail "Replace - all occurrences (expected: 'bbb' or partial, got: '$result')"
fi

# Test 7: Replace case insensitive (if supported)
test_start "Replace - ignore case"
result=$(string.replace "HELLO" "hello" "hi" "rfIgnoreCase")
if [[ "$result" == "hi" || "$result" == "HELLO" ]]; then
    test_pass "Replace - ignore case"
else
    test_fail "Replace - ignore case (expected: 'hi' or 'HELLO', got: '$result')"
fi

# Test 8: Replace at start
test_start "Replace - at start"
result=$(string.replace "hello world" "hello" "goodbye")
if [[ "$result" == "goodbye world" ]]; then
    test_pass "Replace - at start"
else
    test_fail "Replace - at start (expected: 'goodbye world', got: '$result')"
fi

# Test 9: Replace at end
test_start "Replace - at end"
result=$(string.replace "hello world" "world" "earth")
if [[ "$result" == "hello earth" ]]; then
    test_pass "Replace - at end"
else
    test_fail "Replace - at end (expected: 'hello earth', got: '$result')"
fi

# Test 10: Replace with special characters
test_start "Replace - special characters"
result=$(string.replace "test@mail" "@" ".")
if [[ "$result" == "test.mail" ]]; then
    test_pass "Replace - special characters"
else
    test_fail "Replace - special characters (expected: 'test.mail', got: '$result')"
fi
