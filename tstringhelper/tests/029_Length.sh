#!/bin/bash
# Length
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Length" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Length of non-empty string
kt_test_start "Length of string"
result=$(string.length "hello")
if [[ "$result" == "5" ]]; then
    kt_test_pass "Length of string"
else
    kt_test_fail "Length of string (expected: 5, got: '$result')"
fi

# Test 2: Length of empty string
kt_test_start "Length of empty string"
result=$(string.length "")
if [[ "$result" == "0" ]]; then
    kt_test_pass "Length of empty string"
else
    kt_test_fail "Length of empty string (expected: 0, got: '$result')"
fi

# Test 3: Length with spaces
kt_test_start "Length with spaces"
result=$(string.length "hello world")
if [[ "$result" == "11" ]]; then
    kt_test_pass "Length with spaces"
else
    kt_test_fail "Length with spaces (expected: 11, got: '$result')"
fi
