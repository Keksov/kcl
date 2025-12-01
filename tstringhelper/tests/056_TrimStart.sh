#!/bin/bash
# TrimStart
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "TrimStart" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Trim leading spaces
kt_test_start "TrimStart - leading spaces"
result=$(string.trimStart "  hello" " ")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "TrimStart - leading spaces"
else
    kt_test_fail "TrimStart - leading spaces (expected: 'hello', got: '$result')"
fi

# Test 2: Trim leading characters other than spaces
kt_test_start "TrimStart - leading dots"
result=$(string.trimStart "...hello" ".")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "TrimStart - leading dots"
else
    kt_test_fail "TrimStart - leading dots (expected: 'hello', got: '$result')"
fi

# Test 3: No leading characters to trim
kt_test_start "TrimStart - no leading"
result=$(string.trimStart "hello" " ")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "TrimStart - no leading"
else
    kt_test_fail "TrimStart - no leading (expected: 'hello', got: '$result')"
fi

# Test 4: Only leading characters
kt_test_start "TrimStart - only leading"
result=$(string.trimStart "    " " ")
if [[ "$result" == "" ]]; then
    kt_test_pass "TrimStart - only leading"
else
    kt_test_fail "TrimStart - only leading (expected: '', got: '$result')"
fi

# Test 5: Multiple leading character types
kt_test_start "TrimStart - multiple types"
result=$(string.trimStart "..,,hello" ".,")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "TrimStart - multiple types"
else
    kt_test_fail "TrimStart - multiple types (expected: 'hello', got: '$result')"
fi

# Test 6: Single leading character
kt_test_start "TrimStart - single leading"
result=$(string.trimStart " test" " ")
if [[ "$result" == "test" ]]; then
    kt_test_pass "TrimStart - single leading"
else
    kt_test_fail "TrimStart - single leading (expected: 'test', got: '$result')"
fi

# Test 7: Trim with custom delimiter
kt_test_start "TrimStart - custom delimiter"
result=$(string.trimStart ":::abc" ":")
if [[ "$result" == "abc" ]]; then
    kt_test_pass "TrimStart - custom delimiter"
else
    kt_test_fail "TrimStart - custom delimiter (expected: 'abc', got: '$result')"
fi

# Test 8: Empty string
kt_test_start "TrimStart - empty string"
result=$(string.trimStart "" " ")
if [[ "$result" == "" ]]; then
    kt_test_pass "TrimStart - empty string"
else
    kt_test_fail "TrimStart - empty string (expected: '', got: '$result')"
fi

# Test 9: Trailing spaces preserved
kt_test_start "TrimStart - trailing preserved"
result=$(string.trimStart "  hello  " " ")
if [[ "$result" == "hello  " ]]; then
    kt_test_pass "TrimStart - trailing preserved"
else
    kt_test_fail "TrimStart - trailing preserved (expected: 'hello  ', got: '$result')"
fi

# Test 10: Mixed leading characters
kt_test_start "TrimStart - mixed characters"
result=$(string.trimStart "  ;;;  hello" " ;")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "TrimStart - mixed characters"
else
    kt_test_fail "TrimStart - mixed characters (expected: 'hello', got: '$result')"
fi

# Test 11: Note about deprecation
kt_test_start "TrimStart - deprecated method"
# This test verifies the method still works despite being deprecated in favor of TrimLeft
result=$(string.trimStart "  test" " ")
if [[ "$result" == "test" ]]; then
    kt_test_pass "TrimStart - deprecated method"
else
    kt_test_fail "TrimStart - deprecated method (expected: 'test', got: '$result')"
fi

# Test 12: Asterisk as trim character
kt_test_start "TrimStart - asterisk trim"
result=$(string.trimStart "****hello" "*")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "TrimStart - asterisk trim"
else
    kt_test_fail "TrimStart - asterisk trim (expected: 'hello', got: '$result')"
fi
