#!/bin/bash
# IsEmpty
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "IsEmpty" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Empty string is empty
kk_test_start "IsEmpty - empty string"
result=$(string.isEmpty "")
if [[ "$result" == "true" ]]; then
    kk_test_pass "IsEmpty - empty string"
else
    kk_test_fail "IsEmpty - empty string (expected: true, got: '$result')"
fi

# Test 2: Non-empty string
kk_test_start "IsEmpty - non-empty string"
result=$(string.isEmpty "hello")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsEmpty - non-empty string"
else
    kk_test_fail "IsEmpty - non-empty string (expected: false, got: '$result')"
fi

# Test 3: String with spaces
kk_test_start "IsEmpty - string with spaces"
result=$(string.isEmpty "   ")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsEmpty - string with spaces"
else
    kk_test_fail "IsEmpty - string with spaces (expected: false, got: '$result')"
fi

# Test 4: Single space
kk_test_start "IsEmpty - single space"
result=$(string.isEmpty " ")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsEmpty - single space"
else
    kk_test_fail "IsEmpty - single space (expected: false, got: '$result')"
fi

# Test 5: Single character
kk_test_start "IsEmpty - single character"
result=$(string.isEmpty "a")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsEmpty - single character"
else
    kk_test_fail "IsEmpty - single character (expected: false, got: '$result')"
fi

# Test 6: Whitespace and text
kk_test_start "IsEmpty - whitespace and text"
result=$(string.isEmpty " hello ")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsEmpty - whitespace and text"
else
    kk_test_fail "IsEmpty - whitespace and text (expected: false, got: '$result')"
fi

# Test 7: Tab character
kk_test_start "IsEmpty - tab character"
result=$(string.isEmpty "	")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsEmpty - tab character"
else
    kk_test_fail "IsEmpty - tab character (expected: false, got: '$result')"
fi

# Test 8: Newline (if supported)
kk_test_start "IsEmpty - newline character"
result=$(string.isEmpty $'\\n')
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsEmpty - newline character"
else
    kk_test_fail "IsEmpty - newline character (expected: false, got: '$result')"
fi

# Test 9: Zero
kk_test_start "IsEmpty - numeric zero"
result=$(string.isEmpty "0")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsEmpty - numeric zero"
else
    kk_test_fail "IsEmpty - numeric zero (expected: false, got: '$result')"
fi

# Test 10: Long string
kk_test_start "IsEmpty - long string"
result=$(string.isEmpty "This is a much longer string with many characters")
if [[ "$result" == "false" ]]; then
    kk_test_pass "IsEmpty - long string"
else
    kk_test_fail "IsEmpty - long string (expected: false, got: '$result')"
fi
