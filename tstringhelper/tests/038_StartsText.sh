#!/bin/bash
# StartsText
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "StartsText" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: String starts with substring (case insensitive)
kk_test_start "StartsText - starts with"
result=$(string.startsText "hello" "hello world")
if [[ "$result" == "true" ]]; then
    kk_test_pass "StartsText - starts with"
else
    kk_test_fail "StartsText - starts with (expected: true, got: '$result')"
fi

# Test 2: String does not start with substring
kk_test_start "StartsText - does not start with"
result=$(string.startsText "world" "hello world")
if [[ "$result" == "false" ]]; then
    kk_test_pass "StartsText - does not start with"
else
    kk_test_fail "StartsText - does not start with (expected: false, got: '$result')"
fi

# Test 3: Case insensitive matching
kk_test_start "StartsText - case insensitive"
result=$(string.startsText "HELLO" "hello world")
if [[ "$result" == "true" ]]; then
    kk_test_pass "StartsText - case insensitive"
else
    kk_test_fail "StartsText - case insensitive (expected: true, got: '$result')"
fi

# Test 4: Match with mixed case
kk_test_start "StartsText - mixed case"
result=$(string.startsText "HeLLo" "hello world")
if [[ "$result" == "true" ]]; then
    kk_test_pass "StartsText - mixed case"
else
    kk_test_fail "StartsText - mixed case (expected: true, got: '$result')"
fi

# Test 5: Empty substring
kk_test_start "StartsText - empty substring"
result=$(string.startsText "" "hello")
if [[ "$result" == "true" ]]; then
    kk_test_pass "StartsText - empty substring"
else
    kk_test_fail "StartsText - empty substring (expected: true, got: '$result')"
fi

# Test 6: Empty text
kk_test_start "StartsText - empty text"
result=$(string.startsText "hello" "")
if [[ "$result" == "false" ]]; then
    kk_test_pass "StartsText - empty text"
else
    kk_test_fail "StartsText - empty text (expected: false, got: '$result')"
fi

# Test 7: Both empty
kk_test_start "StartsText - both empty"
result=$(string.startsText "" "")
if [[ "$result" == "true" ]]; then
    kk_test_pass "StartsText - both empty"
else
    kk_test_fail "StartsText - both empty (expected: true, got: '$result')"
fi

# Test 8: Substring longer than text
kk_test_start "StartsText - substring longer"
result=$(string.startsText "hello world" "hi")
if [[ "$result" == "false" ]]; then
    kk_test_pass "StartsText - substring longer"
else
    kk_test_fail "StartsText - substring longer (expected: false, got: '$result')"
fi

# Test 9: Exact match
kk_test_start "StartsText - exact match"
result=$(string.startsText "hello" "hello")
if [[ "$result" == "true" ]]; then
    kk_test_pass "StartsText - exact match"
else
    kk_test_fail "StartsText - exact match (expected: true, got: '$result')"
fi

# Test 10: Single character
kk_test_start "StartsText - single character"
result=$(string.startsText "h" "hello")
if [[ "$result" == "true" ]]; then
    kk_test_pass "StartsText - single character"
else
    kk_test_fail "StartsText - single character (expected: true, got: '$result')"
fi
