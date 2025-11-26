#!/bin/bash
# Equals
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Equals" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Equal strings (instance method)
kk_test_start "Equals - equal strings"
result=$(string.equals "hello" "hello")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Equals - equal strings"
else
    kk_test_fail "Equals - equal strings (expected: true, got: '$result')"
fi

# Test 2: Different strings (instance method)
kk_test_start "Equals - different strings"
result=$(string.equals "hello" "world")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Equals - different strings"
else
    kk_test_fail "Equals - different strings (expected: false, got: '$result')"
fi

# Test 3: Case sensitive - different case
kk_test_start "Equals - case sensitive"
result=$(string.equals "Hello" "hello")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Equals - case sensitive"
else
    kk_test_fail "Equals - case sensitive (expected: false, got: '$result')"
fi

# Test 4: Empty strings
kk_test_start "Equals - empty strings"
result=$(string.equals "" "")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Equals - empty strings"
else
    kk_test_fail "Equals - empty strings (expected: true, got: '$result')"
fi

# Test 5: One empty string
kk_test_start "Equals - one empty string"
result=$(string.equals "" "hello")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Equals - one empty string"
else
    kk_test_fail "Equals - one empty string (expected: false, got: '$result')"
fi

# Test 6: Strings with whitespace
kk_test_start "Equals - strings with whitespace"
result=$(string.equals "hello world" "hello world")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Equals - strings with whitespace"
else
    kk_test_fail "Equals - strings with whitespace (expected: true, got: '$result')"
fi

# Test 7: Leading/trailing whitespace difference
kk_test_start "Equals - whitespace mismatch"
result=$(string.equals " hello" "hello ")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Equals - whitespace mismatch"
else
    kk_test_fail "Equals - whitespace mismatch (expected: false, got: '$result')"
fi

# Test 8: Numeric strings
kk_test_start "Equals - numeric strings"
result=$(string.equals "123" "123")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Equals - numeric strings"
else
    kk_test_fail "Equals - numeric strings (expected: true, got: '$result')"
fi

# Test 9: Special characters
kk_test_start "Equals - special characters"
result=$(string.equals "hello@world#123" "hello@world#123")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Equals - special characters"
else
    kk_test_fail "Equals - special characters (expected: true, got: '$result')"
fi

# Test 10: Different special characters
kk_test_start "Equals - different special characters"
result=$(string.equals "hello@world" "hello#world")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Equals - different special characters"
else
    kk_test_fail "Equals - different special characters (expected: false, got: '$result')"
fi
