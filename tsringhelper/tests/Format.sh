#!/bin/bash
# Format.sh - Test string.format static method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Simple string formatting
test_start "Format - simple string substitution"
result=$(string.format "Hello %s" "World")
if [[ "$result" == "Hello World" ]]; then
    test_pass "Format - simple string substitution"
else
    test_fail "Format - simple string substitution (expected: 'Hello World', got: '$result')"
fi

# Test 2: Multiple string substitutions
test_start "Format - multiple substitutions"
result=$(string.format "%s is %s" "This" "great")
if [[ "$result" == "This is great" ]]; then
    test_pass "Format - multiple substitutions"
else
    test_fail "Format - multiple substitutions (expected: 'This is great', got: '$result')"
fi

# Test 3: Integer substitution
test_start "Format - integer substitution"
result=$(string.format "Number: %d" 42)
if [[ "$result" == "Number: 42" ]]; then
    test_pass "Format - integer substitution"
else
    test_fail "Format - integer substitution (expected: 'Number: 42', got: '$result')"
fi

# Test 4: Mixed substitutions
test_start "Format - mixed types"
result=$(string.format "%s has %d apples" "John" 5)
if [[ "$result" == "John has 5 apples" ]]; then
    test_pass "Format - mixed types"
else
    test_fail "Format - mixed types (expected: 'John has 5 apples', got: '$result')"
fi

# Test 5: No substitutions
test_start "Format - no placeholder"
result=$(string.format "Just a string")
if [[ "$result" == "Just a string" ]]; then
    test_pass "Format - no placeholder"
else
    test_fail "Format - no placeholder (expected: 'Just a string', got: '$result')"
fi

# Test 6: Empty format string
test_start "Format - empty format string"
result=$(string.format "")
if [[ "$result" == "" ]]; then
    test_pass "Format - empty format string"
else
    test_fail "Format - empty format string (expected: '', got: '$result')"
fi

# Test 7: Escaped percent sign
test_start "Format - escaped percent"
result=$(string.format "100%% complete")
if [[ "$result" == "100% complete" || "$result" == "100%% complete" ]]; then
    test_pass "Format - escaped percent"
else
    test_fail "Format - escaped percent (expected: '100% complete', got: '$result')"
fi

# Test 8: Three parameters
test_start "Format - three parameters"
result=$(string.format "%s-%s-%s" "a" "b" "c")
if [[ "$result" == "a-b-c" ]]; then
    test_pass "Format - three parameters"
else
    test_fail "Format - three parameters (expected: 'a-b-c', got: '$result')"
fi

# Test 9: String with special characters
test_start "Format - special characters in format"
result=$(string.format "Email: %s@%s" "user" "example.com")
if [[ "$result" == "Email: user@example.com" ]]; then
    test_pass "Format - special characters in format"
else
    test_fail "Format - special characters in format (expected: 'Email: user@example.com', got: '$result')"
fi

# Test 10: Numeric string parameter
test_start "Format - numeric string parameter"
result=$(string.format "ID: %s" "12345")
if [[ "$result" == "ID: 12345" ]]; then
    test_pass "Format - numeric string parameter"
else
    test_fail "Format - numeric string parameter (expected: 'ID: 12345', got: '$result')"
fi
