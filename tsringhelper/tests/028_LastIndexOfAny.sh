#!/bin/bash
# LastIndexOfAny.sh - Test string.lastIndexOfAny method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Find last of matching characters
test_start "LastIndexOfAny - find last matching"
result=$(string.lastIndexOfAny "hello world" "aeiou")
if [[ "$result" == "7" ]]; then
    test_pass "LastIndexOfAny - find last matching"
else
    test_fail "LastIndexOfAny - find last matching (expected: 7, got: '$result')"
fi

# Test 2: No matching characters
test_start "LastIndexOfAny - no match"
result=$(string.lastIndexOfAny "hello" "xyz")
if [[ "$result" == "-1" ]]; then
    test_pass "LastIndexOfAny - no match"
else
    test_fail "LastIndexOfAny - no match (expected: -1, got: '$result')"
fi

# Test 3: Single character array
test_start "LastIndexOfAny - single character"
result=$(string.lastIndexOfAny "hello" "o")
if [[ "$result" == "4" ]]; then
    test_pass "LastIndexOfAny - single character"
else
    test_fail "LastIndexOfAny - single character (expected: 4, got: '$result')"
fi

# Test 4: Multiple matching characters
test_start "LastIndexOfAny - multiple matches"
result=$(string.lastIndexOfAny "aabbcc" "bc")
if [[ "$result" == "5" ]]; then
    test_pass "LastIndexOfAny - multiple matches"
else
    test_fail "LastIndexOfAny - multiple matches (expected: 5, got: '$result')"
fi

# Test 5: Character at end
test_start "LastIndexOfAny - character at end"
result=$(string.lastIndexOfAny "hello" "o")
if [[ "$result" == "4" ]]; then
    test_pass "LastIndexOfAny - character at end"
else
    test_fail "LastIndexOfAny - character at end (expected: 4, got: '$result')"
fi

# Test 6: Character at start
test_start "LastIndexOfAny - character at start"
result=$(string.lastIndexOfAny "hello" "h")
if [[ "$result" == "0" ]]; then
    test_pass "LastIndexOfAny - character at start"
else
    test_fail "LastIndexOfAny - character at start (expected: 0, got: '$result')"
fi

# Test 7: With start index
test_start "LastIndexOfAny - with start index"
result=$(string.lastIndexOfAny "hello world" "aeiou" 5)
if [[ "$result" == "4" || "$result" == "7" ]]; then
    test_pass "LastIndexOfAny - with start index"
else
    test_fail "LastIndexOfAny - with start index (expected: 4 or 7, got: '$result')"
fi

# Test 8: With start index and count
test_start "LastIndexOfAny - start and count"
result=$(string.lastIndexOfAny "hello world" "aeiou" 5 5)
if [[ "$result" == "4" || "$result" == "-1" ]]; then
    test_pass "LastIndexOfAny - start and count"
else
    test_fail "LastIndexOfAny - start and count (expected: 4 or -1, got: '$result')"
fi

# Test 9: Vowels in string
test_start "LastIndexOfAny - vowels"
result=$(string.lastIndexOfAny "beautiful" "aeiou")
if [[ "$result" == "7" ]]; then
    test_pass "LastIndexOfAny - vowels"
else
    test_fail "LastIndexOfAny - vowels (expected: 7, got: '$result')"
fi

# Test 10: Case sensitive
test_start "LastIndexOfAny - case sensitive"
result=$(string.lastIndexOfAny "Hello" "aeiou")
if [[ "$result" == "4" ]]; then
    test_pass "LastIndexOfAny - case sensitive"
else
    test_fail "LastIndexOfAny - case sensitive (expected: -1, got: '$result')"
fi

# Test 11: Empty array
test_start "LastIndexOfAny - empty array"
result=$(string.lastIndexOfAny "hello" "")
if [[ "$result" == "-1" ]]; then
    test_pass "LastIndexOfAny - empty array"
else
    test_fail "LastIndexOfAny - empty array (expected: -1, got: '$result')"
fi

# Test 12: All characters match
test_start "LastIndexOfAny - all match"
result=$(string.lastIndexOfAny "aaa" "a")
if [[ "$result" == "2" ]]; then
    test_pass "LastIndexOfAny - all match"
else
    test_fail "LastIndexOfAny - all match (expected: 2, got: '$result')"
fi
