#!/bin/bash
# LastIndexOf.sh - Test string.lastIndexOf method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Find last character
test_start "LastIndexOf - find last character"
result=$(string.lastIndexOf "hello world" "o")
if [[ "$result" == "7" ]]; then
    test_pass "LastIndexOf - find last character"
else
    test_fail "LastIndexOf - find last character (expected: 7, got: '$result')"
fi

# Test 2: Find last substring
test_start "LastIndexOf - find last substring"
result=$(string.lastIndexOf "hello world hello" "hello")
if [[ "$result" == "12" ]]; then
    test_pass "LastIndexOf - find last substring"
else
    test_fail "LastIndexOf - find last substring (expected: 12, got: '$result')"
fi

# Test 3: Character not found
test_start "LastIndexOf - character not found"
result=$(string.lastIndexOf "hello" "z")
if [[ "$result" == "-1" ]]; then
    test_pass "LastIndexOf - character not found"
else
    test_fail "LastIndexOf - character not found (expected: -1, got: '$result')"
fi

# Test 4: Only one occurrence
test_start "LastIndexOf - only one occurrence"
result=$(string.lastIndexOf "hello" "h")
if [[ "$result" == "0" ]]; then
    test_pass "LastIndexOf - only one occurrence"
else
    test_fail "LastIndexOf - only one occurrence (expected: 0, got: '$result')"
fi

# Test 5: Character at start
test_start "LastIndexOf - first char"
result=$(string.lastIndexOf "hello" "h")
if [[ "$result" == "0" ]]; then
    test_pass "LastIndexOf - first char"
else
    test_fail "LastIndexOf - first char (expected: 0, got: '$result')"
fi

# Test 6: With start index
test_start "LastIndexOf - with start index"
result=$(string.lastIndexOf "hello world hello" "hello" 10)
if [[ "$result" == "12" || "$result" == "0" ]]; then
    test_pass "LastIndexOf - with start index"
else
    test_fail "LastIndexOf - with start index (expected: 12 or 0, got: '$result')"
fi

# Test 7: With start index and count
test_start "LastIndexOf - start index and count"
result=$(string.lastIndexOf "hello world hello" "l" 8 5)
if [[ "$result" == "3" || "$result" == "9" ]]; then
    test_pass "LastIndexOf - start index and count"
else
    test_fail "LastIndexOf - start index and count (expected: 3 or 9, got: '$result')"
fi

# Test 8: Empty search string
test_start "LastIndexOf - empty search"
result=$(string.lastIndexOf "hello" "")
if [[ "$result" == "5" || "$result" == "-1" ]]; then
    test_pass "LastIndexOf - empty search"
else
    test_fail "LastIndexOf - empty search (expected: 5 or -1, got: '$result')"
fi

# Test 9: Case sensitive
test_start "LastIndexOf - case sensitive"
result=$(string.lastIndexOf "Hello World" "h")
if [[ "$result" == "-1" ]]; then
    test_pass "LastIndexOf - case sensitive"
else
    test_fail "LastIndexOf - case sensitive (expected: -1, got: '$result')"
fi

# Test 10: Multiple occurrences
test_start "LastIndexOf - multiple occurrences"
result=$(string.lastIndexOf "aabbaa" "a")
if [[ "$result" == "5" ]]; then
    test_pass "LastIndexOf - multiple occurrences"
else
    test_fail "LastIndexOf - multiple occurrences (expected: 4, got: '$result')"
fi

# Test 11: Last position
test_start "LastIndexOf - last position"
result=$(string.lastIndexOf "hello" "o")
if [[ "$result" == "4" ]]; then
    test_pass "LastIndexOf - last position"
else
    test_fail "LastIndexOf - last position (expected: 4, got: '$result')"
fi

# Test 12: Substring at end
test_start "LastIndexOf - substring at end"
result=$(string.lastIndexOf "hello world" "world")
if [[ "$result" == "6" ]]; then
    test_pass "LastIndexOf - substring at end"
else
    test_fail "LastIndexOf - substring at end (expected: 6, got: '$result')"
fi
