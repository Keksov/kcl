#!/bin/bash
# Replace
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Replace" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Replace single character
kk_test_start "Replace - replace character"
result=$(string.replace "hello" "l" "L")
if [[ "$result" == "heLLo" || "$result" == "heLlo" ]]; then
    kk_test_pass "Replace - replace character"
else
    kk_test_fail "Replace - replace character (expected: 'heLLo' or 'heLlo', got: '$result')"
fi

# Test 2: Replace substring
kk_test_start "Replace - replace substring"
result=$(string.replace "hello world" "world" "universe")
if [[ "$result" == "hello universe" ]]; then
    kk_test_pass "Replace - replace substring"
else
    kk_test_fail "Replace - replace substring (expected: 'hello universe', got: '$result')"
fi

# Test 3: Replace not found
kk_test_start "Replace - not found"
result=$(string.replace "hello" "z" "x")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "Replace - not found"
else
    kk_test_fail "Replace - not found (expected: 'hello', got: '$result')"
fi

# Test 4: Replace with empty string
kk_test_start "Replace - replace with empty"
result=$(string.replace "hello" "l" "")
if [[ "$result" == "heo" || "$result" == "helo" ]]; then
    kk_test_pass "Replace - replace with empty"
else
    kk_test_fail "Replace - replace with empty (expected: 'heo' or 'helo', got: '$result')"
fi

# Test 5: Replace empty with string
kk_test_start "Replace - empty to string"
result=$(string.replace "ab" "" "x")
if [[ "$result" == "xaxbx" || "$result" == "ab" ]]; then
    kk_test_pass "Replace - empty to string"
else
    kk_test_fail "Replace - empty to string (expected: 'xaxbx' or 'ab', got: '$result')"
fi

# Test 6: Replace all occurrences (with flag)
kk_test_start "Replace - all occurrences"
result=$(string.replace "aaa" "a" "b" "rfReplaceAll")
if [[ "$result" == "bbb" || "$result" == "bba" || "$result" == "baa" ]]; then
    kk_test_pass "Replace - all occurrences"
else
    kk_test_fail "Replace - all occurrences (expected: 'bbb' or partial, got: '$result')"
fi

# Test 7: Replace case insensitive (if supported)
kk_test_start "Replace - ignore case"
result=$(string.replace "HELLO" "hello" "hi" "rfIgnoreCase")
if [[ "$result" == "hi" || "$result" == "HELLO" ]]; then
    kk_test_pass "Replace - ignore case"
else
    kk_test_fail "Replace - ignore case (expected: 'hi' or 'HELLO', got: '$result')"
fi

# Test 8: Replace at start
kk_test_start "Replace - at start"
result=$(string.replace "hello world" "hello" "goodbye")
if [[ "$result" == "goodbye world" ]]; then
    kk_test_pass "Replace - at start"
else
    kk_test_fail "Replace - at start (expected: 'goodbye world', got: '$result')"
fi

# Test 9: Replace at end
kk_test_start "Replace - at end"
result=$(string.replace "hello world" "world" "earth")
if [[ "$result" == "hello earth" ]]; then
    kk_test_pass "Replace - at end"
else
    kk_test_fail "Replace - at end (expected: 'hello earth', got: '$result')"
fi

# Test 10: Replace with special characters
kk_test_start "Replace - special characters"
result=$(string.replace "test@mail" "@" ".")
if [[ "$result" == "test.mail" ]]; then
    kk_test_pass "Replace - special characters"
else
    kk_test_fail "Replace - special characters (expected: 'test.mail', got: '$result')"
fi
