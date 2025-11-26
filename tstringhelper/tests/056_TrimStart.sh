#!/bin/bash
# TrimStart
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "TrimStart" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Trim leading spaces
kk_test_start "TrimStart - leading spaces"
result=$(string.trimStart "  hello" " ")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimStart - leading spaces"
else
    kk_test_fail "TrimStart - leading spaces (expected: 'hello', got: '$result')"
fi

# Test 2: Trim leading characters other than spaces
kk_test_start "TrimStart - leading dots"
result=$(string.trimStart "...hello" ".")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimStart - leading dots"
else
    kk_test_fail "TrimStart - leading dots (expected: 'hello', got: '$result')"
fi

# Test 3: No leading characters to trim
kk_test_start "TrimStart - no leading"
result=$(string.trimStart "hello" " ")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimStart - no leading"
else
    kk_test_fail "TrimStart - no leading (expected: 'hello', got: '$result')"
fi

# Test 4: Only leading characters
kk_test_start "TrimStart - only leading"
result=$(string.trimStart "    " " ")
if [[ "$result" == "" ]]; then
    kk_test_pass "TrimStart - only leading"
else
    kk_test_fail "TrimStart - only leading (expected: '', got: '$result')"
fi

# Test 5: Multiple leading character types
kk_test_start "TrimStart - multiple types"
result=$(string.trimStart "..,,hello" ".,")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimStart - multiple types"
else
    kk_test_fail "TrimStart - multiple types (expected: 'hello', got: '$result')"
fi

# Test 6: Single leading character
kk_test_start "TrimStart - single leading"
result=$(string.trimStart " test" " ")
if [[ "$result" == "test" ]]; then
    kk_test_pass "TrimStart - single leading"
else
    kk_test_fail "TrimStart - single leading (expected: 'test', got: '$result')"
fi

# Test 7: Trim with custom delimiter
kk_test_start "TrimStart - custom delimiter"
result=$(string.trimStart ":::abc" ":")
if [[ "$result" == "abc" ]]; then
    kk_test_pass "TrimStart - custom delimiter"
else
    kk_test_fail "TrimStart - custom delimiter (expected: 'abc', got: '$result')"
fi

# Test 8: Empty string
kk_test_start "TrimStart - empty string"
result=$(string.trimStart "" " ")
if [[ "$result" == "" ]]; then
    kk_test_pass "TrimStart - empty string"
else
    kk_test_fail "TrimStart - empty string (expected: '', got: '$result')"
fi

# Test 9: Trailing spaces preserved
kk_test_start "TrimStart - trailing preserved"
result=$(string.trimStart "  hello  " " ")
if [[ "$result" == "hello  " ]]; then
    kk_test_pass "TrimStart - trailing preserved"
else
    kk_test_fail "TrimStart - trailing preserved (expected: 'hello  ', got: '$result')"
fi

# Test 10: Mixed leading characters
kk_test_start "TrimStart - mixed characters"
result=$(string.trimStart "  ;;;  hello" " ;")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimStart - mixed characters"
else
    kk_test_fail "TrimStart - mixed characters (expected: 'hello', got: '$result')"
fi

# Test 11: Note about deprecation
kk_test_start "TrimStart - deprecated method"
# This test verifies the method still works despite being deprecated in favor of TrimLeft
result=$(string.trimStart "  test" " ")
if [[ "$result" == "test" ]]; then
    kk_test_pass "TrimStart - deprecated method"
else
    kk_test_fail "TrimStart - deprecated method (expected: 'test', got: '$result')"
fi

# Test 12: Asterisk as trim character
kk_test_start "TrimStart - asterisk trim"
result=$(string.trimStart "****hello" "*")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimStart - asterisk trim"
else
    kk_test_fail "TrimStart - asterisk trim (expected: 'hello', got: '$result')"
fi
