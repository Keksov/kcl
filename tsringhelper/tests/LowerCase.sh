#!/bin/bash
# LowerCase.sh - Test string.lowerCase static method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Convert uppercase to lowercase
test_start "LowerCase - uppercase to lowercase"
result=$(string.lowerCase "HELLO")
if [[ "$result" == "hello" ]]; then
    test_pass "LowerCase - uppercase to lowercase"
else
    test_fail "LowerCase - uppercase to lowercase (expected: 'hello', got: '$result')"
fi

# Test 2: Already lowercase
test_start "LowerCase - already lowercase"
result=$(string.lowerCase "hello")
if [[ "$result" == "hello" ]]; then
    test_pass "LowerCase - already lowercase"
else
    test_fail "LowerCase - already lowercase (expected: 'hello', got: '$result')"
fi

# Test 3: Mixed case
test_start "LowerCase - mixed case"
result=$(string.lowerCase "HeLLo WoRLd")
if [[ "$result" == "hello world" ]]; then
    test_pass "LowerCase - mixed case"
else
    test_fail "LowerCase - mixed case (expected: 'hello world', got: '$result')"
fi

# Test 4: Empty string
test_start "LowerCase - empty string"
result=$(string.lowerCase "")
if [[ "$result" == "" ]]; then
    test_pass "LowerCase - empty string"
else
    test_fail "LowerCase - empty string (expected: '', got: '$result')"
fi

# Test 5: With numbers
test_start "LowerCase - with numbers"
result=$(string.lowerCase "HELLO123WORLD")
if [[ "$result" == "hello123world" ]]; then
    test_pass "LowerCase - with numbers"
else
    test_fail "LowerCase - with numbers (expected: 'hello123world', got: '$result')"
fi

# Test 6: With special characters
test_start "LowerCase - special characters"
result=$(string.lowerCase "HELLO@WORLD#123")
if [[ "$result" == "hello@world#123" ]]; then
    test_pass "LowerCase - special characters"
else
    test_fail "LowerCase - special characters (expected: 'hello@world#123', got: '$result')"
fi

# Test 7: Single uppercase character
test_start "LowerCase - single uppercase"
result=$(string.lowerCase "A")
if [[ "$result" == "a" ]]; then
    test_pass "LowerCase - single uppercase"
else
    test_fail "LowerCase - single uppercase (expected: 'a', got: '$result')"
fi

# Test 8: All uppercase
test_start "LowerCase - all uppercase"
result=$(string.lowerCase "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
if [[ "$result" == "abcdefghijklmnopqrstuvwxyz" ]]; then
    test_pass "LowerCase - all uppercase"
else
    test_fail "LowerCase - all uppercase (expected: 'abcdefghijklmnopqrstuvwxyz', got: '$result')"
fi

# Test 9: With spaces
test_start "LowerCase - with spaces"
result=$(string.lowerCase "HELLO  WORLD  TEST")
if [[ "$result" == "hello  world  test" ]]; then
    test_pass "LowerCase - with spaces"
else
    test_fail "LowerCase - with spaces (expected: 'hello  world  test', got: '$result')"
fi

# Test 10: Only ASCII (7-bit)
test_start "LowerCase - ASCII only"
result=$(string.lowerCase "TESTSTRING")
if [[ "$result" == "teststring" ]]; then
    test_pass "LowerCase - ASCII only"
else
    test_fail "LowerCase - ASCII only (expected: 'teststring', got: '$result')"
fi
