#!/bin/bash
# StartsText
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "StartsText" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: String starts with substring (case insensitive)
kt_test_start "StartsText - starts with"
result=$(string.startsText "hello" "hello world")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - starts with"
else
    kt_test_fail "StartsText - starts with (expected: true, got: '$result')"
fi

# Test 2: String does not start with substring
kt_test_start "StartsText - does not start with"
result=$(string.startsText "world" "hello world")
if [[ "$result" == "false" ]]; then
    kt_test_pass "StartsText - does not start with"
else
    kt_test_fail "StartsText - does not start with (expected: false, got: '$result')"
fi

# Test 3: Case insensitive matching
kt_test_start "StartsText - case insensitive"
result=$(string.startsText "HELLO" "hello world")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - case insensitive"
else
    kt_test_fail "StartsText - case insensitive (expected: true, got: '$result')"
fi

# Test 4: Match with mixed case
kt_test_start "StartsText - mixed case"
result=$(string.startsText "HeLLo" "hello world")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - mixed case"
else
    kt_test_fail "StartsText - mixed case (expected: true, got: '$result')"
fi

# Test 5: Empty substring
kt_test_start "StartsText - empty substring"
result=$(string.startsText "" "hello")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - empty substring"
else
    kt_test_fail "StartsText - empty substring (expected: true, got: '$result')"
fi

# Test 6: Empty text
kt_test_start "StartsText - empty text"
result=$(string.startsText "hello" "")
if [[ "$result" == "false" ]]; then
    kt_test_pass "StartsText - empty text"
else
    kt_test_fail "StartsText - empty text (expected: false, got: '$result')"
fi

# Test 7: Both empty
kt_test_start "StartsText - both empty"
result=$(string.startsText "" "")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - both empty"
else
    kt_test_fail "StartsText - both empty (expected: true, got: '$result')"
fi

# Test 8: Substring longer than text
kt_test_start "StartsText - substring longer"
result=$(string.startsText "hello world" "hi")
if [[ "$result" == "false" ]]; then
    kt_test_pass "StartsText - substring longer"
else
    kt_test_fail "StartsText - substring longer (expected: false, got: '$result')"
fi

# Test 9: Exact match
kt_test_start "StartsText - exact match"
result=$(string.startsText "hello" "hello")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - exact match"
else
    kt_test_fail "StartsText - exact match (expected: true, got: '$result')"
fi

# Test 10: Single character
kt_test_start "StartsText - single character"
result=$(string.startsText "h" "hello")
if [[ "$result" == "true" ]]; then
    kt_test_pass "StartsText - single character"
else
    kt_test_fail "StartsText - single character (expected: true, got: '$result')"
fi
