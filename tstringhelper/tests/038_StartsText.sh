#!/bin/bash
# StartsText.sh - Test string.startsText static method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: String starts with substring (case insensitive)
test_start "StartsText - starts with"
result=$(string.startsText "hello" "hello world")
if [[ "$result" == "true" ]]; then
    test_pass "StartsText - starts with"
else
    test_fail "StartsText - starts with (expected: true, got: '$result')"
fi

# Test 2: String does not start with substring
test_start "StartsText - does not start with"
result=$(string.startsText "world" "hello world")
if [[ "$result" == "false" ]]; then
    test_pass "StartsText - does not start with"
else
    test_fail "StartsText - does not start with (expected: false, got: '$result')"
fi

# Test 3: Case insensitive matching
test_start "StartsText - case insensitive"
result=$(string.startsText "HELLO" "hello world")
if [[ "$result" == "true" ]]; then
    test_pass "StartsText - case insensitive"
else
    test_fail "StartsText - case insensitive (expected: true, got: '$result')"
fi

# Test 4: Match with mixed case
test_start "StartsText - mixed case"
result=$(string.startsText "HeLLo" "hello world")
if [[ "$result" == "true" ]]; then
    test_pass "StartsText - mixed case"
else
    test_fail "StartsText - mixed case (expected: true, got: '$result')"
fi

# Test 5: Empty substring
test_start "StartsText - empty substring"
result=$(string.startsText "" "hello")
if [[ "$result" == "true" ]]; then
    test_pass "StartsText - empty substring"
else
    test_fail "StartsText - empty substring (expected: true, got: '$result')"
fi

# Test 6: Empty text
test_start "StartsText - empty text"
result=$(string.startsText "hello" "")
if [[ "$result" == "false" ]]; then
    test_pass "StartsText - empty text"
else
    test_fail "StartsText - empty text (expected: false, got: '$result')"
fi

# Test 7: Both empty
test_start "StartsText - both empty"
result=$(string.startsText "" "")
if [[ "$result" == "true" ]]; then
    test_pass "StartsText - both empty"
else
    test_fail "StartsText - both empty (expected: true, got: '$result')"
fi

# Test 8: Substring longer than text
test_start "StartsText - substring longer"
result=$(string.startsText "hello world" "hi")
if [[ "$result" == "false" ]]; then
    test_pass "StartsText - substring longer"
else
    test_fail "StartsText - substring longer (expected: false, got: '$result')"
fi

# Test 9: Exact match
test_start "StartsText - exact match"
result=$(string.startsText "hello" "hello")
if [[ "$result" == "true" ]]; then
    test_pass "StartsText - exact match"
else
    test_fail "StartsText - exact match (expected: true, got: '$result')"
fi

# Test 10: Single character
test_start "StartsText - single character"
result=$(string.startsText "h" "hello")
if [[ "$result" == "true" ]]; then
    test_pass "StartsText - single character"
else
    test_fail "StartsText - single character (expected: true, got: '$result')"
fi
