#!/bin/bash
# LowerCase
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "LowerCase" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert uppercase to lowercase
kt_test_start "LowerCase - uppercase to lowercase"
result=$(string.lowerCase "HELLO")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "LowerCase - uppercase to lowercase"
else
    kt_test_fail "LowerCase - uppercase to lowercase (expected: 'hello', got: '$result')"
fi

# Test 2: Already lowercase
kt_test_start "LowerCase - already lowercase"
result=$(string.lowerCase "hello")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "LowerCase - already lowercase"
else
    kt_test_fail "LowerCase - already lowercase (expected: 'hello', got: '$result')"
fi

# Test 3: Mixed case
kt_test_start "LowerCase - mixed case"
result=$(string.lowerCase "HeLLo WoRLd")
if [[ "$result" == "hello world" ]]; then
    kt_test_pass "LowerCase - mixed case"
else
    kt_test_fail "LowerCase - mixed case (expected: 'hello world', got: '$result')"
fi

# Test 4: Empty string
kt_test_start "LowerCase - empty string"
result=$(string.lowerCase "")
if [[ "$result" == "" ]]; then
    kt_test_pass "LowerCase - empty string"
else
    kt_test_fail "LowerCase - empty string (expected: '', got: '$result')"
fi

# Test 5: With numbers
kt_test_start "LowerCase - with numbers"
result=$(string.lowerCase "HELLO123WORLD")
if [[ "$result" == "hello123world" ]]; then
    kt_test_pass "LowerCase - with numbers"
else
    kt_test_fail "LowerCase - with numbers (expected: 'hello123world', got: '$result')"
fi

# Test 6: With special characters
kt_test_start "LowerCase - special characters"
result=$(string.lowerCase "HELLO@WORLD#123")
if [[ "$result" == "hello@world#123" ]]; then
    kt_test_pass "LowerCase - special characters"
else
    kt_test_fail "LowerCase - special characters (expected: 'hello@world#123', got: '$result')"
fi

# Test 7: Single uppercase character
kt_test_start "LowerCase - single uppercase"
result=$(string.lowerCase "A")
if [[ "$result" == "a" ]]; then
    kt_test_pass "LowerCase - single uppercase"
else
    kt_test_fail "LowerCase - single uppercase (expected: 'a', got: '$result')"
fi

# Test 8: All uppercase
kt_test_start "LowerCase - all uppercase"
result=$(string.lowerCase "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
if [[ "$result" == "abcdefghijklmnopqrstuvwxyz" ]]; then
    kt_test_pass "LowerCase - all uppercase"
else
    kt_test_fail "LowerCase - all uppercase (expected: 'abcdefghijklmnopqrstuvwxyz', got: '$result')"
fi

# Test 9: With spaces
kt_test_start "LowerCase - with spaces"
result=$(string.lowerCase "HELLO  WORLD  TEST")
if [[ "$result" == "hello  world  test" ]]; then
    kt_test_pass "LowerCase - with spaces"
else
    kt_test_fail "LowerCase - with spaces (expected: 'hello  world  test', got: '$result')"
fi

# Test 10: Only ASCII (7-bit)
kt_test_start "LowerCase - ASCII only"
result=$(string.lowerCase "TESTSTRING")
if [[ "$result" == "teststring" ]]; then
    kt_test_pass "LowerCase - ASCII only"
else
    kt_test_fail "LowerCase - ASCII only (expected: 'teststring', got: '$result')"
fi
