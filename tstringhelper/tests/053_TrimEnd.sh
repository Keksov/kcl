#!/bin/bash
# TrimEnd
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "TrimEnd" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Trim trailing spaces
kk_test_start "TrimEnd - trailing spaces"
result=$(string.trimEnd "hello  " " ")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimEnd - trailing spaces"
else
    kk_test_fail "TrimEnd - trailing spaces (expected: 'hello', got: '$result')"
fi

# Test 2: Trim trailing characters other than spaces
kk_test_start "TrimEnd - trailing dots"
result=$(string.trimEnd "hello..." ".")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimEnd - trailing dots"
else
    kk_test_fail "TrimEnd - trailing dots (expected: 'hello', got: '$result')"
fi

# Test 3: No trailing characters to trim
kk_test_start "TrimEnd - no trailing"
result=$(string.trimEnd "hello" " ")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimEnd - no trailing"
else
    kk_test_fail "TrimEnd - no trailing (expected: 'hello', got: '$result')"
fi

# Test 4: Only trailing characters
kk_test_start "TrimEnd - only trailing"
result=$(string.trimEnd "    " " ")
if [[ "$result" == "" ]]; then
    kk_test_pass "TrimEnd - only trailing"
else
    kk_test_fail "TrimEnd - only trailing (expected: '', got: '$result')"
fi

# Test 5: Multiple trailing character types
kk_test_start "TrimEnd - multiple types"
result=$(string.trimEnd "hello...,," ".,")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimEnd - multiple types"
else
    kk_test_fail "TrimEnd - multiple types (expected: 'hello', got: '$result')"
fi

# Test 6: Single trailing character
kk_test_start "TrimEnd - single trailing"
result=$(string.trimEnd "test " " ")
if [[ "$result" == "test" ]]; then
    kk_test_pass "TrimEnd - single trailing"
else
    kk_test_fail "TrimEnd - single trailing (expected: 'test', got: '$result')"
fi

# Test 7: Trim with custom delimiter
kk_test_start "TrimEnd - custom delimiter"
result=$(string.trimEnd "abc:::" ":")
if [[ "$result" == "abc" ]]; then
    kk_test_pass "TrimEnd - custom delimiter"
else
    kk_test_fail "TrimEnd - custom delimiter (expected: 'abc', got: '$result')"
fi

# Test 8: Empty string
kk_test_start "TrimEnd - empty string"
result=$(string.trimEnd "" " ")
if [[ "$result" == "" ]]; then
    kk_test_pass "TrimEnd - empty string"
else
    kk_test_fail "TrimEnd - empty string (expected: '', got: '$result')"
fi

# Test 9: Leading spaces preserved
kk_test_start "TrimEnd - leading preserved"
result=$(string.trimEnd "  hello  " " ")
if [[ "$result" == "  hello" ]]; then
    kk_test_pass "TrimEnd - leading preserved"
else
    kk_test_fail "TrimEnd - leading preserved (expected: '  hello', got: '$result')"
fi

# Test 10: Mixed trailing characters
kk_test_start "TrimEnd - mixed characters"
result=$(string.trimEnd "hello  ;;;  " " ;")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimEnd - mixed characters"
else
    kk_test_fail "TrimEnd - mixed characters (expected: 'hello', got: '$result')"
fi

# Test 11: Note about deprecation
kk_test_start "TrimEnd - deprecated method"
# This test verifies the method still works despite being deprecated in favor of TrimRight
result=$(string.trimEnd "test  " " ")
if [[ "$result" == "test" ]]; then
    kk_test_pass "TrimEnd - deprecated method"
else
    kk_test_fail "TrimEnd - deprecated method (expected: 'test', got: '$result')"
fi

# Test 12: Asterisk as trim character
kk_test_start "TrimEnd - asterisk trim"
result=$(string.trimEnd "hello****" "*")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "TrimEnd - asterisk trim"
else
    kk_test_fail "TrimEnd - asterisk trim (expected: 'hello', got: '$result')"
fi
