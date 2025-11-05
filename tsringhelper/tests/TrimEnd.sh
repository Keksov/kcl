#!/bin/bash
# TrimEnd.sh - Test string.trimEnd deprecated method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Trim trailing spaces
test_start "TrimEnd - trailing spaces"
result=$(string.trimEnd "hello  " " ")
if [[ "$result" == "hello" ]]; then
    test_pass "TrimEnd - trailing spaces"
else
    test_fail "TrimEnd - trailing spaces (expected: 'hello', got: '$result')"
fi

# Test 2: Trim trailing characters other than spaces
test_start "TrimEnd - trailing dots"
result=$(string.trimEnd "hello..." ".")
if [[ "$result" == "hello" ]]; then
    test_pass "TrimEnd - trailing dots"
else
    test_fail "TrimEnd - trailing dots (expected: 'hello', got: '$result')"
fi

# Test 3: No trailing characters to trim
test_start "TrimEnd - no trailing"
result=$(string.trimEnd "hello" " ")
if [[ "$result" == "hello" ]]; then
    test_pass "TrimEnd - no trailing"
else
    test_fail "TrimEnd - no trailing (expected: 'hello', got: '$result')"
fi

# Test 4: Only trailing characters
test_start "TrimEnd - only trailing"
result=$(string.trimEnd "    " " ")
if [[ "$result" == "" ]]; then
    test_pass "TrimEnd - only trailing"
else
    test_fail "TrimEnd - only trailing (expected: '', got: '$result')"
fi

# Test 5: Multiple trailing character types
test_start "TrimEnd - multiple types"
result=$(string.trimEnd "hello...,," ".,")
if [[ "$result" == "hello" ]]; then
    test_pass "TrimEnd - multiple types"
else
    test_fail "TrimEnd - multiple types (expected: 'hello', got: '$result')"
fi

# Test 6: Single trailing character
test_start "TrimEnd - single trailing"
result=$(string.trimEnd "test " " ")
if [[ "$result" == "test" ]]; then
    test_pass "TrimEnd - single trailing"
else
    test_fail "TrimEnd - single trailing (expected: 'test', got: '$result')"
fi

# Test 7: Trim with custom delimiter
test_start "TrimEnd - custom delimiter"
result=$(string.trimEnd "abc:::" ":")
if [[ "$result" == "abc" ]]; then
    test_pass "TrimEnd - custom delimiter"
else
    test_fail "TrimEnd - custom delimiter (expected: 'abc', got: '$result')"
fi

# Test 8: Empty string
test_start "TrimEnd - empty string"
result=$(string.trimEnd "" " ")
if [[ "$result" == "" ]]; then
    test_pass "TrimEnd - empty string"
else
    test_fail "TrimEnd - empty string (expected: '', got: '$result')"
fi

# Test 9: Leading spaces preserved
test_start "TrimEnd - leading preserved"
result=$(string.trimEnd "  hello  " " ")
if [[ "$result" == "  hello" ]]; then
    test_pass "TrimEnd - leading preserved"
else
    test_fail "TrimEnd - leading preserved (expected: '  hello', got: '$result')"
fi

# Test 10: Mixed trailing characters
test_start "TrimEnd - mixed characters"
result=$(string.trimEnd "hello  ;;;  " " ;")
if [[ "$result" == "hello" ]]; then
    test_pass "TrimEnd - mixed characters"
else
    test_fail "TrimEnd - mixed characters (expected: 'hello', got: '$result')"
fi

# Test 11: Note about deprecation
test_start "TrimEnd - deprecated method"
# This test verifies the method still works despite being deprecated in favor of TrimRight
result=$(string.trimEnd "test  " " ")
if [[ "$result" == "test" ]]; then
    test_pass "TrimEnd - deprecated method"
else
    test_fail "TrimEnd - deprecated method (expected: 'test', got: '$result')"
fi

# Test 12: Asterisk as trim character
test_start "TrimEnd - asterisk trim"
result=$(string.trimEnd "hello****" "*")
if [[ "$result" == "hello" ]]; then
    test_pass "TrimEnd - asterisk trim"
else
    test_fail "TrimEnd - asterisk trim (expected: 'hello', got: '$result')"
fi
