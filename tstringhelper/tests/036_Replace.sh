#!/bin/bash
# Replace
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Replace" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Replace single character
kt_test_start "Replace - replace character"
result=$(string.replace "hello" "l" "L")
if [[ "$result" == "heLlo" ]]; then
    kt_test_pass "Replace - replace character"
else
    kt_test_fail "Replace - replace character (expected: 'heLlo', got: '$result')"
fi

# Test 2: Replace substring
kt_test_start "Replace - replace substring"
result=$(string.replace "hello world" "world" "universe")
if [[ "$result" == "hello universe" ]]; then
    kt_test_pass "Replace - replace substring"
else
    kt_test_fail "Replace - replace substring (expected: 'hello universe', got: '$result')"
fi

# Test 3: Replace not found
kt_test_start "Replace - not found"
result=$(string.replace "hello" "z" "x")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Replace - not found"
else
    kt_test_fail "Replace - not found (expected: 'hello', got: '$result')"
fi

# Test 4: Replace with empty string
kt_test_start "Replace - replace with empty"
result=$(string.replace "hello" "l" "")
if [[ "$result" == "helo" ]]; then
    kt_test_pass "Replace - replace with empty"
else
    kt_test_fail "Replace - replace with empty (expected: 'helo', got: '$result')"
fi

# Test 5: Replace empty with string
kt_test_start "Replace - empty to string"
result=$(string.replace "ab" "" "x")
if [[ "$result" == "ab" ]]; then
    kt_test_pass "Replace - empty to string"
else
    kt_test_fail "Replace - empty to string (expected: 'ab', got: '$result')"
fi

# Test 6: Replace all occurrences (with flag)
kt_test_start "Replace - all occurrences"
result=$(string.replace "aaa" "a" "b" "rfReplaceAll")
if [[ "$result" == "bbb" ]]; then
    kt_test_pass "Replace - all occurrences"
else
    kt_test_fail "Replace - all occurrences (expected: 'bbb', got: '$result')"
fi

# Test 7: Replace case insensitive (if supported)
kt_test_start "Replace - ignore case"
result=$(string.replace "HELLO" "hello" "hi" "rfIgnoreCase")
if [[ "$result" == "hi" ]]; then
    kt_test_pass "Replace - ignore case"
else
    kt_test_fail "Replace - ignore case (expected: 'hi', got: '$result')"
fi

# Test 8: Replace at start
kt_test_start "Replace - at start"
result=$(string.replace "hello world" "hello" "goodbye")
if [[ "$result" == "goodbye world" ]]; then
    kt_test_pass "Replace - at start"
else
    kt_test_fail "Replace - at start (expected: 'goodbye world', got: '$result')"
fi

# Test 9: Replace at end
kt_test_start "Replace - at end"
result=$(string.replace "hello world" "world" "earth")
if [[ "$result" == "hello earth" ]]; then
    kt_test_pass "Replace - at end"
else
    kt_test_fail "Replace - at end (expected: 'hello earth', got: '$result')"
fi

# Test 10: Replace with special characters
kt_test_start "Replace - special characters"
result=$(string.replace "test@mail" "@" ".")
if [[ "$result" == "test.mail" ]]; then
    kt_test_pass "Replace - special characters"
else
    kt_test_fail "Replace - special characters (expected: 'test.mail', got: '$result')"
fi

# Test 11: Replace treats glob metacharacters literally
kt_test_start "Replace - literal glob metacharacter"
result=$(string.replace "a*b*c" "*" "X" "rfReplaceAll")
if [[ "$result" == "aXbXc" ]]; then
    kt_test_pass "Replace - literal glob metacharacter"
else
    kt_test_fail "Replace - literal glob metacharacter (expected: 'aXbXc', got: '$result')"
fi

# Test 12: Ignore-case replace treats search text literally
kt_test_start "Replace - ignore case literal text"
result=$(string.replace "a.b axb A.B" "a.b" "X" "rfReplaceAll rfIgnoreCase")
if [[ "$result" == "X axb X" ]]; then
    kt_test_pass "Replace - ignore case literal text"
else
    kt_test_fail "Replace - ignore case literal text (expected: 'X axb X', got: '$result')"
fi
