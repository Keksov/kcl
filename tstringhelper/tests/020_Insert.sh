#!/bin/bash
# Insert.sh - Test string.insert method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Insert at start
test_start "Insert - at start"
result=$(string.insert "world" 0 "hello ")
if [[ "$result" == "hello world" ]]; then
    test_pass "Insert - at start"
else
    test_fail "Insert - at start (expected: 'hello world', got: '$result')"
fi

# Test 2: Insert in middle
test_start "Insert - in middle"
result=$(string.insert "heo" 2 "ll")
if [[ "$result" == "hello" ]]; then
    test_pass "Insert - in middle"
else
    test_fail "Insert - in middle (expected: 'hello', got: '$result')"
fi

# Test 3: Insert at end
test_start "Insert - at end"
result=$(string.insert "hello" 5 " world")
if [[ "$result" == "hello world" ]]; then
    test_pass "Insert - at end"
else
    test_fail "Insert - at end (expected: 'hello world', got: '$result')"
fi

# Test 4: Insert empty string
test_start "Insert - empty string"
result=$(string.insert "hello" 2 "")
if [[ "$result" == "hello" ]]; then
    test_pass "Insert - empty string"
else
    test_fail "Insert - empty string (expected: 'hello', got: '$result')"
fi

# Test 5: Insert into empty string
test_start "Insert - into empty string"
result=$(string.insert "" 0 "hello")
if [[ "$result" == "hello" ]]; then
    test_pass "Insert - into empty string"
else
    test_fail "Insert - into empty string (expected: 'hello', got: '$result')"
fi

# Test 6: Insert multiple characters
test_start "Insert - multiple characters"
result=$(string.insert "heo" 2 "lll")
if [[ "$result" == "helllo" ]]; then
    test_pass "Insert - multiple characters"
else
    test_fail "Insert - multiple characters (expected: 'hellloeo', got: '$result')"
fi

# Test 7: Insert with spaces
test_start "Insert - with spaces"
result=$(string.insert "hello world" 5 "  ")
if [[ "$result" == "hello   world" ]]; then
    test_pass "Insert - with spaces"
else
    test_fail "Insert - with spaces (expected: 'hello   world', got: '$result')"
fi

# Test 8: Insert special characters
test_start "Insert - special characters"
result=$(string.insert "hello@" 5 ".")
if [[ "$result" == "hello.@" ]]; then
    test_pass "Insert - special characters"
else
    test_fail "Insert - special characters (expected: 'hello.@', got: '$result')"
fi

# Test 9: Insert numeric string
test_start "Insert - numeric string"
result=$(string.insert "123" 1 "00")
if [[ "$result" == "10023" ]]; then
    test_pass "Insert - numeric string"
else
    test_fail "Insert - numeric string (expected: '10023', got: '$result')"
fi

# Test 10: Insert at position equal to length
test_start "Insert - at position equal to length"
result=$(string.insert "test" 4 "ing")
if [[ "$result" == "testing" ]]; then
    test_pass "Insert - at position equal to length"
else
    test_fail "Insert - at position equal to length (expected: 'testing', got: '$result')"
fi

# Test 11: Insert long string
test_start "Insert - long string insertion"
result=$(string.insert "beginning end" 10 "middle ")
if [[ "$result" == "beginning middle end" ]]; then
    test_pass "Insert - long string insertion"
else
    test_fail "Insert - long string insertion (expected: 'beginning middle end', got: '$result')"
fi

# Test 12: Single character insertion
test_start "Insert - single character"
result=$(string.insert "hllo" 1 "e")
if [[ "$result" == "hello" ]]; then
    test_pass "Insert - single character"
else
    test_fail "Insert - single character (expected: 'hello', got: '$result')"
fi
