#!/bin/bash
# Contains.sh - Test string.contains method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: String contains substring
test_start "Contains substring"
result=$(string.contains "hello world" "world")
if [[ "$result" == "true" ]]; then
    test_pass "Contains substring"
else
    test_fail "Contains substring (expected: true, got: '$result')"
fi

# Test 2: String does not contain substring
test_start "Does not contain substring"
result=$(string.contains "hello world" "test")
if [[ "$result" == "false" ]]; then
    test_pass "Does not contain substring"
else
    test_fail "Does not contain substring (expected: false, got: '$result')"
fi

# Test 3: Empty substring
test_start "Contains empty string"
result=$(string.contains "hello" "")
if [[ "$result" == "true" ]]; then
    test_pass "Contains empty string"
else
    test_fail "Contains empty string (expected: true, got: '$result')"
fi

# Test 4: Substring at start
test_start "Contains at start"
result=$(string.contains "hello world" "hello")
if [[ "$result" == "true" ]]; then
    test_pass "Contains at start"
else
    test_fail "Contains at start (expected: true, got: '$result')"
fi

# Test 5: Substring at end
test_start "Contains at end"
result=$(string.contains "hello world" "world")
if [[ "$result" == "true" ]]; then
    test_pass "Contains at end"
else
    test_fail "Contains at end (expected: true, got: '$result')"
fi

# Test 6: Case sensitivity
test_start "Case sensitive contains"
result=$(string.contains "Hello World" "hello")
if [[ "$result" == "false" ]]; then
    test_pass "Case sensitive contains"
else
    test_fail "Case sensitive contains (expected: false, got: '$result')"
fi
