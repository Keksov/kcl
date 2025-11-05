#!/bin/bash
# EndsWith.sh - Test string.endsWith method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: String ends with substring (case sensitive)
test_start "EndsWith - case sensitive match"
result=$(string.endsWith "hello world" "world")
if [[ "$result" == "true" ]]; then
    test_pass "EndsWith - case sensitive match"
else
    test_fail "EndsWith - case sensitive match (expected: true, got: '$result')"
fi

# Test 2: String does not end with substring
test_start "EndsWith - no match"
result=$(string.endsWith "hello world" "hello")
if [[ "$result" == "false" ]]; then
    test_pass "EndsWith - no match"
else
    test_fail "EndsWith - no match (expected: false, got: '$result')"
fi

# Test 3: Case sensitive - different case
test_start "EndsWith - case mismatch"
result=$(string.endsWith "hello world" "WORLD")
if [[ "$result" == "false" ]]; then
    test_pass "EndsWith - case mismatch"
else
    test_fail "EndsWith - case mismatch (expected: false, got: '$result')"
fi

# Test 4: Empty suffix
test_start "EndsWith - empty suffix"
result=$(string.endsWith "hello" "")
if [[ "$result" == "true" ]]; then
    test_pass "EndsWith - empty suffix"
else
    test_fail "EndsWith - empty suffix (expected: true, got: '$result')"
fi

# Test 5: Suffix longer than string
test_start "EndsWith - suffix longer than string"
result=$(string.endsWith "hi" "hello world")
if [[ "$result" == "false" ]]; then
    test_pass "EndsWith - suffix longer than string"
else
    test_fail "EndsWith - suffix longer than string (expected: false, got: '$result')"
fi

# Test 6: Exact match
test_start "EndsWith - exact match"
result=$(string.endsWith "hello" "hello")
if [[ "$result" == "true" ]]; then
    test_pass "EndsWith - exact match"
else
    test_fail "EndsWith - exact match (expected: true, got: '$result')"
fi

# Test 7: Single character match
test_start "EndsWith - single character match"
result=$(string.endsWith "hello" "o")
if [[ "$result" == "true" ]]; then
    test_pass "EndsWith - single character match"
else
    test_fail "EndsWith - single character match (expected: true, got: '$result')"
fi

# Test 8: Empty string
test_start "EndsWith - empty string"
result=$(string.endsWith "" "test")
if [[ "$result" == "false" ]]; then
    test_pass "EndsWith - empty string"
else
    test_fail "EndsWith - empty string (expected: false, got: '$result')"
fi

# Test 9: EndsWith with IgnoreCase parameter (if supported)
test_start "EndsWith - ignore case true"
result=$(string.endsWith "hello world" "WORLD" true)
if [[ "$result" == "true" || "$result" == "error" ]]; then
    test_pass "EndsWith - ignore case true"
else
    test_fail "EndsWith - ignore case true (expected: true or error, got: '$result')"
fi

# Test 10: With special characters
test_start "EndsWith - special characters"
result=$(string.endsWith "hello.txt" ".txt")
if [[ "$result" == "true" ]]; then
    test_pass "EndsWith - special characters"
else
    test_fail "EndsWith - special characters (expected: true, got: '$result')"
fi
