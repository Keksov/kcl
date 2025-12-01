#!/bin/bash
# IsEmpty
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "IsEmpty" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Empty string is empty
kt_test_start "IsEmpty - empty string"
result=$(string.isEmpty "")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsEmpty - empty string"
else
    kt_test_fail "IsEmpty - empty string (expected: true, got: '$result')"
fi

# Test 2: Non-empty string
kt_test_start "IsEmpty - non-empty string"
result=$(string.isEmpty "hello")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - non-empty string"
else
    kt_test_fail "IsEmpty - non-empty string (expected: false, got: '$result')"
fi

# Test 3: String with spaces
kt_test_start "IsEmpty - string with spaces"
result=$(string.isEmpty "   ")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - string with spaces"
else
    kt_test_fail "IsEmpty - string with spaces (expected: false, got: '$result')"
fi

# Test 4: Single space
kt_test_start "IsEmpty - single space"
result=$(string.isEmpty " ")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - single space"
else
    kt_test_fail "IsEmpty - single space (expected: false, got: '$result')"
fi

# Test 5: Single character
kt_test_start "IsEmpty - single character"
result=$(string.isEmpty "a")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - single character"
else
    kt_test_fail "IsEmpty - single character (expected: false, got: '$result')"
fi

# Test 6: Whitespace and text
kt_test_start "IsEmpty - whitespace and text"
result=$(string.isEmpty " hello ")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - whitespace and text"
else
    kt_test_fail "IsEmpty - whitespace and text (expected: false, got: '$result')"
fi

# Test 7: Tab character
kt_test_start "IsEmpty - tab character"
result=$(string.isEmpty "	")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - tab character"
else
    kt_test_fail "IsEmpty - tab character (expected: false, got: '$result')"
fi

# Test 8: Newline (if supported)
kt_test_start "IsEmpty - newline character"
result=$(string.isEmpty $'\\n')
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - newline character"
else
    kt_test_fail "IsEmpty - newline character (expected: false, got: '$result')"
fi

# Test 9: Zero
kt_test_start "IsEmpty - numeric zero"
result=$(string.isEmpty "0")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - numeric zero"
else
    kt_test_fail "IsEmpty - numeric zero (expected: false, got: '$result')"
fi

# Test 10: Long string
kt_test_start "IsEmpty - long string"
result=$(string.isEmpty "This is a much longer string with many characters")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - long string"
else
    kt_test_fail "IsEmpty - long string (expected: false, got: '$result')"
fi
