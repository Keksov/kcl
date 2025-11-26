#!/bin/bash
# LowerCase
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "LowerCase" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert uppercase to lowercase
kk_test_start "LowerCase - uppercase to lowercase"
result=$(string.lowerCase "HELLO")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "LowerCase - uppercase to lowercase"
else
    kk_test_fail "LowerCase - uppercase to lowercase (expected: 'hello', got: '$result')"
fi

# Test 2: Already lowercase
kk_test_start "LowerCase - already lowercase"
result=$(string.lowerCase "hello")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "LowerCase - already lowercase"
else
    kk_test_fail "LowerCase - already lowercase (expected: 'hello', got: '$result')"
fi

# Test 3: Mixed case
kk_test_start "LowerCase - mixed case"
result=$(string.lowerCase "HeLLo WoRLd")
if [[ "$result" == "hello world" ]]; then
    kk_test_pass "LowerCase - mixed case"
else
    kk_test_fail "LowerCase - mixed case (expected: 'hello world', got: '$result')"
fi

# Test 4: Empty string
kk_test_start "LowerCase - empty string"
result=$(string.lowerCase "")
if [[ "$result" == "" ]]; then
    kk_test_pass "LowerCase - empty string"
else
    kk_test_fail "LowerCase - empty string (expected: '', got: '$result')"
fi

# Test 5: With numbers
kk_test_start "LowerCase - with numbers"
result=$(string.lowerCase "HELLO123WORLD")
if [[ "$result" == "hello123world" ]]; then
    kk_test_pass "LowerCase - with numbers"
else
    kk_test_fail "LowerCase - with numbers (expected: 'hello123world', got: '$result')"
fi

# Test 6: With special characters
kk_test_start "LowerCase - special characters"
result=$(string.lowerCase "HELLO@WORLD#123")
if [[ "$result" == "hello@world#123" ]]; then
    kk_test_pass "LowerCase - special characters"
else
    kk_test_fail "LowerCase - special characters (expected: 'hello@world#123', got: '$result')"
fi

# Test 7: Single uppercase character
kk_test_start "LowerCase - single uppercase"
result=$(string.lowerCase "A")
if [[ "$result" == "a" ]]; then
    kk_test_pass "LowerCase - single uppercase"
else
    kk_test_fail "LowerCase - single uppercase (expected: 'a', got: '$result')"
fi

# Test 8: All uppercase
kk_test_start "LowerCase - all uppercase"
result=$(string.lowerCase "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
if [[ "$result" == "abcdefghijklmnopqrstuvwxyz" ]]; then
    kk_test_pass "LowerCase - all uppercase"
else
    kk_test_fail "LowerCase - all uppercase (expected: 'abcdefghijklmnopqrstuvwxyz', got: '$result')"
fi

# Test 9: With spaces
kk_test_start "LowerCase - with spaces"
result=$(string.lowerCase "HELLO  WORLD  TEST")
if [[ "$result" == "hello  world  test" ]]; then
    kk_test_pass "LowerCase - with spaces"
else
    kk_test_fail "LowerCase - with spaces (expected: 'hello  world  test', got: '$result')"
fi

# Test 10: Only ASCII (7-bit)
kk_test_start "LowerCase - ASCII only"
result=$(string.lowerCase "TESTSTRING")
if [[ "$result" == "teststring" ]]; then
    kk_test_pass "LowerCase - ASCII only"
else
    kk_test_fail "LowerCase - ASCII only (expected: 'teststring', got: '$result')"
fi
