#!/bin/bash
# IsNullOrWhiteSpace
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "IsNullOrWhiteSpace" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Empty string
kk_test_start "IsNullOrWhiteSpace - empty string"
result=$(string.isNullOrWhiteSpace "")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - empty string"
else
    kk_test_fail "IsNullOrWhiteSpace - empty string (expected: true, got: '$result')"
fi

# Test 2: Spaces only
kk_test_start "IsNullOrWhiteSpace - spaces only"
result=$(string.isNullOrWhiteSpace "   ")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - spaces only"
else
    kk_test_fail "IsNullOrWhiteSpace - spaces only (expected: true, got: '$result')"
fi

# Test 3: Tab only
kk_test_start "IsNullOrWhiteSpace - tab only"
result=$(string.isNullOrWhiteSpace "	")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - tab only"
else
    kk_test_fail "IsNullOrWhiteSpace - tab only (expected: true, got: '$result')"
fi

# Test 4: Mixed whitespace
kk_test_start "IsNullOrWhiteSpace - mixed whitespace"
result=$(string.isNullOrWhiteSpace "  	  ")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - mixed whitespace"
else
    kk_test_fail "IsNullOrWhiteSpace - mixed whitespace (expected: true, got: '$result')"
fi

# Test 5: Non-empty string
kk_test_start "IsNullOrWhiteSpace - non-empty string"
result=$(string.isNullOrWhiteSpace "hello")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - non-empty string"
else
    kk_test_fail "IsNullOrWhiteSpace - non-empty string (expected: false, got: '$result')"
fi

# Test 6: Spaces with text
kk_test_start "IsNullOrWhiteSpace - spaces with text"
result=$(string.isNullOrWhiteSpace " hello ")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - spaces with text"
else
    kk_test_fail "IsNullOrWhiteSpace - spaces with text (expected: false, got: '$result')"
fi

# Test 7: Single space
kk_test_start "IsNullOrWhiteSpace - single space"
result=$(string.isNullOrWhiteSpace " ")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - single space"
else
    kk_test_fail "IsNullOrWhiteSpace - single space (expected: true, got: '$result')"
fi

# Test 8: Numeric string
kk_test_start "IsNullOrWhiteSpace - numeric string"
result=$(string.isNullOrWhiteSpace "123")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - numeric string"
else
    kk_test_fail "IsNullOrWhiteSpace - numeric string (expected: false, got: '$result')"
fi

# Test 9: Single character
kk_test_start "IsNullOrWhiteSpace - single character"
result=$(string.isNullOrWhiteSpace "a")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - single character"
else
    kk_test_fail "IsNullOrWhiteSpace - single character (expected: false, got: '$result')"
fi

# Test 10: Zero string
kk_test_start "IsNullOrWhiteSpace - zero string"
result=$(string.isNullOrWhiteSpace "0")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - zero string"
else
    kk_test_fail "IsNullOrWhiteSpace - zero string (expected: false, got: '$result')"
fi

# Test 11: Long whitespace string
kk_test_start "IsNullOrWhiteSpace - long whitespace"
result=$(string.isNullOrWhiteSpace "                                   ")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - long whitespace"
else
    kk_test_fail "IsNullOrWhiteSpace - long whitespace (expected: true, got: '$result')"
fi

# Test 12: Whitespace with special character
kk_test_start "IsNullOrWhiteSpace - whitespace and special"
result=$(string.isNullOrWhiteSpace "  .  ")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsNullOrWhiteSpace - whitespace and special"
else
    kk_test_fail "IsNullOrWhiteSpace - whitespace and special (expected: false, got: '$result')"
fi
