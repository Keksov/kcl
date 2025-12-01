#!/bin/bash
# Trim
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Trim" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Trim spaces
kt_test_start "Trim leading and trailing spaces"
result=$(string.trim "  hello world  ")
if [[ "$result" == "hello world" ]]; then
    kt_test_pass "Trim leading and trailing spaces"
else
    kt_test_fail "Trim leading and trailing spaces (expected: 'hello world', got: '$result')"
fi

# Test 2: No spaces to trim
kt_test_start "Trim no spaces"
result=$(string.trim "hello")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Trim no spaces"
else
    kt_test_fail "Trim no spaces (expected: 'hello', got: '$result')"
fi

# Test 3: Only spaces
kt_test_start "Trim only spaces"
result=$(string.trim "   ")
if [[ "$result" == "" ]]; then
    kt_test_pass "Trim only spaces"
else
    kt_test_fail "Trim only spaces (expected: '', got: '$result')"
fi

# Test 4: Leading spaces
kt_test_start "Trim leading spaces"
result=$(string.trim "  hello")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Trim leading spaces"
else
    kt_test_fail "Trim leading spaces (expected: 'hello', got: '$result')"
fi

# Test 5: Trailing spaces
kt_test_start "Trim trailing spaces"
result=$(string.trim "hello  ")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Trim trailing spaces"
else
    kt_test_fail "Trim trailing spaces (expected: 'hello', got: '$result')"
fi
