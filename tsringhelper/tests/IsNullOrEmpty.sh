#!/bin/bash
# IsNullOrEmpty.sh - Test string.isNullOrEmpty static method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Empty string
test_start "IsNullOrEmpty - empty string"
result=$(string.isNullOrEmpty "")
if [[ "$result" == "true" ]]; then
    test_pass "IsNullOrEmpty - empty string"
else
    test_fail "IsNullOrEmpty - empty string (expected: true, got: '$result')"
fi

# Test 2: Non-empty string
test_start "IsNullOrEmpty - non-empty string"
result=$(string.isNullOrEmpty "hello")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrEmpty - non-empty string"
else
    test_fail "IsNullOrEmpty - non-empty string (expected: false, got: '$result')"
fi

# Test 3: String with spaces only
test_start "IsNullOrEmpty - spaces only"
result=$(string.isNullOrEmpty "   ")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrEmpty - spaces only"
else
    test_fail "IsNullOrEmpty - spaces only (expected: false, got: '$result')"
fi

# Test 4: Single space
test_start "IsNullOrEmpty - single space"
result=$(string.isNullOrEmpty " ")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrEmpty - single space"
else
    test_fail "IsNullOrEmpty - single space (expected: false, got: '$result')"
fi

# Test 5: String with leading spaces
test_start "IsNullOrEmpty - leading spaces"
result=$(string.isNullOrEmpty "   hello")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrEmpty - leading spaces"
else
    test_fail "IsNullOrEmpty - leading spaces (expected: false, got: '$result')"
fi

# Test 6: String with trailing spaces
test_start "IsNullOrEmpty - trailing spaces"
result=$(string.isNullOrEmpty "hello   ")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrEmpty - trailing spaces"
else
    test_fail "IsNullOrEmpty - trailing spaces (expected: false, got: '$result')"
fi

# Test 7: Single character
test_start "IsNullOrEmpty - single character"
result=$(string.isNullOrEmpty "a")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrEmpty - single character"
else
    test_fail "IsNullOrEmpty - single character (expected: false, got: '$result')"
fi

# Test 8: Whitespace characters (tab)
test_start "IsNullOrEmpty - tab character"
result=$(string.isNullOrEmpty "	")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrEmpty - tab character"
else
    test_fail "IsNullOrEmpty - tab character (expected: false, got: '$result')"
fi

# Test 9: Numeric string
test_start "IsNullOrEmpty - numeric string"
result=$(string.isNullOrEmpty "123")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrEmpty - numeric string"
else
    test_fail "IsNullOrEmpty - numeric string (expected: false, got: '$result')"
fi

# Test 10: Zero string
test_start "IsNullOrEmpty - zero string"
result=$(string.isNullOrEmpty "0")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrEmpty - zero string"
else
    test_fail "IsNullOrEmpty - zero string (expected: false, got: '$result')"
fi

# Test 11: Long string
test_start "IsNullOrEmpty - long string"
result=$(string.isNullOrEmpty "This is a very long string with many characters")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrEmpty - long string"
else
    test_fail "IsNullOrEmpty - long string (expected: false, got: '$result')"
fi

# Test 12: Special characters
test_start "IsNullOrEmpty - special characters"
result=$(string.isNullOrEmpty "!@#$%^&*()")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrEmpty - special characters"
else
    test_fail "IsNullOrEmpty - special characters (expected: false, got: '$result')"
fi
