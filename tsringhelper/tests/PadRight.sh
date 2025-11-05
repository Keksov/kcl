#!/bin/bash
# PadRight.sh - Test string.padRight method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Pad to wider width with spaces
test_start "PadRight - pad with spaces"
result=$(string.padRight "hello" 10)
if [[ "$result" == "hello     " ]]; then
    test_pass "PadRight - pad with spaces"
else
    test_fail "PadRight - pad with spaces (expected: 'hello     ', got: '$result')"
fi

# Test 2: String already at width
test_start "PadRight - already at width"
result=$(string.padRight "hello" 5)
if [[ "$result" == "hello" ]]; then
    test_pass "PadRight - already at width"
else
    test_fail "PadRight - already at width (expected: 'hello', got: '$result')"
fi

# Test 3: String longer than width
test_start "PadRight - longer than width"
result=$(string.padRight "hello world" 5)
if [[ "$result" == "hello world" ]]; then
    test_pass "PadRight - longer than width"
else
    test_fail "PadRight - longer than width (expected: 'hello world', got: '$result')"
fi

# Test 4: Empty string padding
test_start "PadRight - empty string"
result=$(string.padRight "" 5)
if [[ "$result" == "     " ]]; then
    test_pass "PadRight - empty string"
else
    test_fail "PadRight - empty string (expected: '     ', got: '$result')"
fi

# Test 5: Custom padding character
test_start "PadRight - custom character"
result=$(string.padRight "42" 5 "*")
if [[ "$result" == "42***" ]]; then
    test_pass "PadRight - custom character"
else
    test_fail "PadRight - custom character (expected: '42***', got: '$result')"
fi

# Test 6: Pad with dot
test_start "PadRight - pad with dot"
result=$(string.padRight "test" 8 ".")
if [[ "$result" == "test...." ]]; then
    test_pass "PadRight - pad with dot"
else
    test_fail "PadRight - pad with dot (expected: 'test....', got: '$result')"
fi

# Test 7: Single character padding
test_start "PadRight - single character"
result=$(string.padRight "x" 4 "-")
if [[ "$result" == "x---" ]]; then
    test_pass "PadRight - single character"
else
    test_fail "PadRight - single character (expected: 'x---', got: '$result')"
fi

# Test 8: Width of 1
test_start "PadRight - width of 1"
result=$(string.padRight "a" 1)
if [[ "$result" == "a" ]]; then
    test_pass "PadRight - width of 1"
else
    test_fail "PadRight - width of 1 (expected: 'a', got: '$result')"
fi

# Test 9: Large padding
test_start "PadRight - large padding"
result=$(string.padRight "a" 10 "+")
if [[ "$result" == "a+++++++++" ]]; then
    test_pass "PadRight - large padding"
else
    test_fail "PadRight - large padding (expected: 'a+++++++++', got: '$result')"
fi

# Test 10: Hash character padding
test_start "PadRight - hash padding"
result=$(string.padRight "data" 8 "#")
if [[ "$result" == "data####" ]]; then
    test_pass "PadRight - hash padding"
else
    test_fail "PadRight - hash padding (expected: 'data####', got: '$result')"
fi
