#!/bin/bash
# IndexOfAny.sh - Test string.indexOfAny method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Find first character from array
test_start "IndexOfAny - find first matching character"
result=$(string.indexOfAny "hello world" "w")
if [[ "$result" == "6" ]]; then
    test_pass "IndexOfAny - find first matching character"
else
    test_fail "IndexOfAny - find first matching character (expected: 6, got: '$result')"
fi

# Test 2: Find first of multiple characters
test_start "IndexOfAny - multiple characters"
result=$(string.indexOfAny "hello world" "owx")
if [[ "$result" == "4" ]]; then
    test_pass "IndexOfAny - multiple characters"
else
    test_fail "IndexOfAny - multiple characters (expected: 4, got: '$result')"
fi

# Test 3: No matching character
test_start "IndexOfAny - no match"
result=$(string.indexOfAny "hello" "xyz")
if [[ "$result" == "-1" ]]; then
    test_pass "IndexOfAny - no match"
else
    test_fail "IndexOfAny - no match (expected: -1, got: '$result')"
fi

# Test 4: Match at start
test_start "IndexOfAny - match at start"
result=$(string.indexOfAny "hello" "he")
if [[ "$result" == "0" ]]; then
    test_pass "IndexOfAny - match at start"
else
    test_fail "IndexOfAny - match at start (expected: 0, got: '$result')"
fi

# Test 5: Match at end
test_start "IndexOfAny - match at end"
result=$(string.indexOfAny "hello" "o")
if [[ "$result" == "4" ]]; then
    test_pass "IndexOfAny - match at end"
else
    test_fail "IndexOfAny - match at end (expected: 4, got: '$result')"
fi

# Test 6: With start index
test_start "IndexOfAny - with start index"
result=$(string.indexOfAny "hello world" "aeiou" 5)
if [[ "$result" == "7" ]]; then
    test_pass "IndexOfAny - with start index"
else
    test_fail "IndexOfAny - with start index (expected: 7, got: '$result')"
fi

# Test 7: With start index and count
test_start "IndexOfAny - start index and count"
result=$(string.indexOfAny "This is a string" "is" 9 4)
if [[ "$result" == "10" || "$result" == "13" ]]; then
    test_pass "IndexOfAny - start index and count"
else
    test_fail "IndexOfAny - start index and count (expected: 10 or 13, got: '$result')"
fi

# Test 8: Empty character array
test_start "IndexOfAny - empty array"
result=$(string.indexOfAny "hello" "")
if [[ "$result" == "-1" ]]; then
    test_pass "IndexOfAny - empty array"
else
    test_fail "IndexOfAny - empty array (expected: -1, got: '$result')"
fi

# Test 9: Single character from multiple
test_start "IndexOfAny - single match from multiple"
result=$(string.indexOfAny "hello world" "ws")
if [[ "$result" == "6" ]]; then
    test_pass "IndexOfAny - single match from multiple"
else
    test_fail "IndexOfAny - single match from multiple (expected: 6, got: '$result')"
fi

# Test 10: Case sensitive search
test_start "IndexOfAny - case sensitive"
result=$(string.indexOfAny "Hello World" "w")
if [[ "$result" == "-1" ]]; then
    test_pass "IndexOfAny - case sensitive"
else
    test_fail "IndexOfAny - case sensitive (expected: -1, got: '$result')"
fi

# Test 11: Invalid start index
test_start "IndexOfAny - invalid start index"
result=$(string.indexOfAny "hello" "aeiou" 20)
if [[ "$result" == "-1" ]]; then
    test_pass "IndexOfAny - invalid start index"
else
    test_fail "IndexOfAny - invalid start index (expected: -1, got: '$result')"
fi

# Test 12: Count larger than remaining string
test_start "IndexOfAny - count larger than remaining"
result=$(string.indexOfAny "hello" "h" 0 100)
if [[ "$result" == "0" ]]; then
    test_pass "IndexOfAny - count larger than remaining"
else
    test_fail "IndexOfAny - count larger than remaining (expected: 0, got: '$result')"
fi
