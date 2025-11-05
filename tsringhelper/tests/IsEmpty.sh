#!/bin/bash
# IsEmpty.sh - Test string.isEmpty method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Empty string is empty
test_start "IsEmpty - empty string"
result=$(string.isEmpty "")
if [[ "$result" == "true" ]]; then
    test_pass "IsEmpty - empty string"
else
    test_fail "IsEmpty - empty string (expected: true, got: '$result')"
fi

# Test 2: Non-empty string
test_start "IsEmpty - non-empty string"
result=$(string.isEmpty "hello")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - non-empty string"
else
    test_fail "IsEmpty - non-empty string (expected: false, got: '$result')"
fi

# Test 3: String with spaces
test_start "IsEmpty - string with spaces"
result=$(string.isEmpty "   ")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - string with spaces"
else
    test_fail "IsEmpty - string with spaces (expected: false, got: '$result')"
fi

# Test 4: Single space
test_start "IsEmpty - single space"
result=$(string.isEmpty " ")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - single space"
else
    test_fail "IsEmpty - single space (expected: false, got: '$result')"
fi

# Test 5: Single character
test_start "IsEmpty - single character"
result=$(string.isEmpty "a")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - single character"
else
    test_fail "IsEmpty - single character (expected: false, got: '$result')"
fi

# Test 6: Whitespace and text
test_start "IsEmpty - whitespace and text"
result=$(string.isEmpty " hello ")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - whitespace and text"
else
    test_fail "IsEmpty - whitespace and text (expected: false, got: '$result')"
fi

# Test 7: Tab character
test_start "IsEmpty - tab character"
result=$(string.isEmpty "	")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - tab character"
else
    test_fail "IsEmpty - tab character (expected: false, got: '$result')"
fi

# Test 8: Newline (if supported)
test_start "IsEmpty - newline character"
result=$(string.isEmpty $'\\n')
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - newline character"
else
    test_fail "IsEmpty - newline character (expected: false, got: '$result')"
fi

# Test 9: Zero
test_start "IsEmpty - numeric zero"
result=$(string.isEmpty "0")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - numeric zero"
else
    test_fail "IsEmpty - numeric zero (expected: false, got: '$result')"
fi

# Test 10: Long string
test_start "IsEmpty - long string"
result=$(string.isEmpty "This is a much longer string with many characters")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - long string"
else
    test_fail "IsEmpty - long string (expected: false, got: '$result')"
fi
