#!/bin/bash
# Chars
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Chars" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Get char at index
kt_test_start "Get char at index"
result=$(string.chars "hello" 0)
if [[ "$result" == "h" ]]; then
    kt_test_pass "Get char at index"
else
    kt_test_fail "Get char at index (expected: 'h', got: '$result')"
fi

# Test 2: Invalid index
kt_test_start "Invalid index"
result=$(string.chars "hello" 10)
if [[ "$result" == "undefined" ]]; then
    kt_test_pass "Invalid index"
else
    kt_test_fail "Invalid index (expected: 'undefined', got: '$result')"
fi
