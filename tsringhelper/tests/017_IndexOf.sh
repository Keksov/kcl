#!/bin/bash
# IndexOf.sh - Test string.indexOf method with various overloads

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Find character in string
test_start "IndexOf - find character"
result=$(string.indexOf "hello" "l")
if [[ "$result" == "2" ]]; then
    test_pass "IndexOf - find character"
else
    test_fail "IndexOf - find character (expected: 2, got: '$result')"
fi

# Test 2: Find substring in string
test_start "IndexOf - find substring"
result=$(string.indexOf "hello world" "world")
if [[ "$result" == "6" ]]; then
    test_pass "IndexOf - find substring"
else
    test_fail "IndexOf - find substring (expected: 6, got: '$result')"
fi

# Test 3: Character not found
test_start "IndexOf - character not found"
result=$(string.indexOf "hello" "z")
if [[ "$result" == "-1" ]]; then
    test_pass "IndexOf - character not found"
else
    test_fail "IndexOf - character not found (expected: -1, got: '$result')"
fi

# Test 4: Character at start
test_start "IndexOf - character at start"
result=$(string.indexOf "hello" "h")
if [[ "$result" == "0" ]]; then
    test_pass "IndexOf - character at start"
else
    test_fail "IndexOf - character at start (expected: 0, got: '$result')"
fi

# Test 5: Character at end
test_start "IndexOf - character at end"
result=$(string.indexOf "hello" "o")
if [[ "$result" == "4" ]]; then
    test_pass "IndexOf - character at end"
else
    test_fail "IndexOf - character at end (expected: 4, got: '$result')"
fi

# Test 6: Find with start index
test_start "IndexOf - with start index"
result=$(string.indexOf "hello world" "o" 5)
if [[ "$result" == "7" ]]; then
    test_pass "IndexOf - with start index"
else
    test_fail "IndexOf - with start index (expected: 7, got: '$result')"
fi

# Test 7: Find substring with start index
test_start "IndexOf - substring with start index"
result=$(string.indexOf "hello world hello" "hello" 1)
if [[ "$result" == "12" ]]; then
    test_pass "IndexOf - substring with start index"
else
    test_fail "IndexOf - substring with start index (expected: 12, got: '$result')"
fi

# Test 8: With start index and count
test_start "IndexOf - with start index and count"
result=$(string.indexOf "This is a string" "s" 8 4)
if [[ "$result" == "10" ]]; then
    test_pass "IndexOf - with start index and count"
else
    test_fail "IndexOf - with start index and count (expected: 10, got: '$result')"
fi

# Test 9: Empty string search
test_start "IndexOf - empty search string"
result=$(string.indexOf "hello" "")
if [[ "$result" == "0" || "$result" == "-1" ]]; then
    test_pass "IndexOf - empty search string"
else
    test_fail "IndexOf - empty search string (expected: 0 or -1, got: '$result')"
fi

# Test 10: Case sensitive search
test_start "IndexOf - case sensitive"
result=$(string.indexOf "Hello World" "h")
if [[ "$result" == "-1" ]]; then
    test_pass "IndexOf - case sensitive"
else
    test_fail "IndexOf - case sensitive (expected: -1, got: '$result')"
fi

# Test 11: First occurrence
test_start "IndexOf - first occurrence"
result=$(string.indexOf "aabbaa" "a")
if [[ "$result" == "0" ]]; then
    test_pass "IndexOf - first occurrence"
else
    test_fail "IndexOf - first occurrence (expected: 0, got: '$result')"
fi

# Test 12: Invalid start index (beyond string length)
test_start "IndexOf - invalid start index"
result=$(string.indexOf "hello" "l" 10)
if [[ "$result" == "-1" ]]; then
    test_pass "IndexOf - invalid start index"
else
    test_fail "IndexOf - invalid start index (expected: -1, got: '$result')"
fi
