#!/bin/bash
# Remove.sh - Test string.remove method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Remove from start index
test_start "Remove - from start index"
result=$(string.remove "hello world" 5)
if [[ "$result" == "hello" ]]; then
    test_pass "Remove - from start index"
else
    test_fail "Remove - from start index (expected: 'hello', got: '$result')"
fi

# Test 2: Remove with count
test_start "Remove - with count"
result=$(string.remove "hello world" 0 5)
if [[ "$result" == " world" ]]; then
    test_pass "Remove - with count"
else
    test_fail "Remove - with count (expected: ' world', got: '$result')"
fi

# Test 3: Remove entire string
test_start "Remove - entire string"
result=$(string.remove "hello" 0 5)
if [[ "$result" == "" ]]; then
    test_pass "Remove - entire string"
else
    test_fail "Remove - entire string (expected: '', got: '$result')"
fi

# Test 4: Remove nothing (start at end)
test_start "Remove - nothing from end"
result=$(string.remove "hello" 5)
if [[ "$result" == "hello" ]]; then
    test_pass "Remove - nothing from end"
else
    test_fail "Remove - nothing from end (expected: 'hello', got: '$result')"
fi

# Test 5: Remove middle section
test_start "Remove - middle section"
result=$(string.remove "hello world test" 5 6)
if [[ "$result" == "hellotest" ]]; then
    test_pass "Remove - middle section"
else
    test_fail "Remove - middle section (expected: 'hellotest', got: '$result')"
fi

# Test 6: Remove single character
test_start "Remove - single character"
result=$(string.remove "hello" 2 1)
if [[ "$result" == "helo" ]]; then
    test_pass "Remove - single character"
else
    test_fail "Remove - single character (expected: 'helo', got: '$result')"
fi

# Test 7: Remove from position 0
test_start "Remove - from position 0"
result=$(string.remove "test" 0 2)
if [[ "$result" == "st" ]]; then
    test_pass "Remove - from position 0"
else
    test_fail "Remove - from position 0 (expected: 'st', got: '$result')"
fi

# Test 8: Remove with count larger than remaining
test_start "Remove - count larger than string"
result=$(string.remove "hello" 2 100)
if [[ "$result" == "he" ]]; then
    test_pass "Remove - count larger than string"
else
    test_fail "Remove - count larger than string (expected: 'he', got: '$result')"
fi

# Test 9: Remove last character
test_start "Remove - last character"
result=$(string.remove "hello" 4 1)
if [[ "$result" == "hell" ]]; then
    test_pass "Remove - last character"
else
    test_fail "Remove - last character (expected: 'hell', got: '$result')"
fi

# Test 10: Remove everything except first
test_start "Remove - keep only first"
result=$(string.remove "hello world" 1)
if [[ "$result" == "h" ]]; then
    test_pass "Remove - keep only first"
else
    test_fail "Remove - keep only first (expected: 'h', got: '$result')"
fi
