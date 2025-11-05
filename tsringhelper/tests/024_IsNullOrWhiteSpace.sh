#!/bin/bash
# IsNullOrWhiteSpace.sh - Test string.isNullOrWhiteSpace static method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Empty string
test_start "IsNullOrWhiteSpace - empty string"
result=$(string.isNullOrWhiteSpace "")
if [[ "$result" == "true" ]]; then
    test_pass "IsNullOrWhiteSpace - empty string"
else
    test_fail "IsNullOrWhiteSpace - empty string (expected: true, got: '$result')"
fi

# Test 2: Spaces only
test_start "IsNullOrWhiteSpace - spaces only"
result=$(string.isNullOrWhiteSpace "   ")
if [[ "$result" == "true" ]]; then
    test_pass "IsNullOrWhiteSpace - spaces only"
else
    test_fail "IsNullOrWhiteSpace - spaces only (expected: true, got: '$result')"
fi

# Test 3: Tab only
test_start "IsNullOrWhiteSpace - tab only"
result=$(string.isNullOrWhiteSpace "	")
if [[ "$result" == "true" ]]; then
    test_pass "IsNullOrWhiteSpace - tab only"
else
    test_fail "IsNullOrWhiteSpace - tab only (expected: true, got: '$result')"
fi

# Test 4: Mixed whitespace
test_start "IsNullOrWhiteSpace - mixed whitespace"
result=$(string.isNullOrWhiteSpace "  	  ")
if [[ "$result" == "true" ]]; then
    test_pass "IsNullOrWhiteSpace - mixed whitespace"
else
    test_fail "IsNullOrWhiteSpace - mixed whitespace (expected: true, got: '$result')"
fi

# Test 5: Non-empty string
test_start "IsNullOrWhiteSpace - non-empty string"
result=$(string.isNullOrWhiteSpace "hello")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrWhiteSpace - non-empty string"
else
    test_fail "IsNullOrWhiteSpace - non-empty string (expected: false, got: '$result')"
fi

# Test 6: Spaces with text
test_start "IsNullOrWhiteSpace - spaces with text"
result=$(string.isNullOrWhiteSpace " hello ")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrWhiteSpace - spaces with text"
else
    test_fail "IsNullOrWhiteSpace - spaces with text (expected: false, got: '$result')"
fi

# Test 7: Single space
test_start "IsNullOrWhiteSpace - single space"
result=$(string.isNullOrWhiteSpace " ")
if [[ "$result" == "true" ]]; then
    test_pass "IsNullOrWhiteSpace - single space"
else
    test_fail "IsNullOrWhiteSpace - single space (expected: true, got: '$result')"
fi

# Test 8: Numeric string
test_start "IsNullOrWhiteSpace - numeric string"
result=$(string.isNullOrWhiteSpace "123")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrWhiteSpace - numeric string"
else
    test_fail "IsNullOrWhiteSpace - numeric string (expected: false, got: '$result')"
fi

# Test 9: Single character
test_start "IsNullOrWhiteSpace - single character"
result=$(string.isNullOrWhiteSpace "a")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrWhiteSpace - single character"
else
    test_fail "IsNullOrWhiteSpace - single character (expected: false, got: '$result')"
fi

# Test 10: Zero string
test_start "IsNullOrWhiteSpace - zero string"
result=$(string.isNullOrWhiteSpace "0")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrWhiteSpace - zero string"
else
    test_fail "IsNullOrWhiteSpace - zero string (expected: false, got: '$result')"
fi

# Test 11: Long whitespace string
test_start "IsNullOrWhiteSpace - long whitespace"
result=$(string.isNullOrWhiteSpace "                                   ")
if [[ "$result" == "true" ]]; then
    test_pass "IsNullOrWhiteSpace - long whitespace"
else
    test_fail "IsNullOrWhiteSpace - long whitespace (expected: true, got: '$result')"
fi

# Test 12: Whitespace with special character
test_start "IsNullOrWhiteSpace - whitespace and special"
result=$(string.isNullOrWhiteSpace "  .  ")
if [[ "$result" == "false" ]]; then
    test_pass "IsNullOrWhiteSpace - whitespace and special"
else
    test_fail "IsNullOrWhiteSpace - whitespace and special (expected: false, got: '$result')"
fi
