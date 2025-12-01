#!/bin/bash
# UpperCase
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "UpperCase" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Upper case
kt_test_start "Upper case"
result=$(string.upperCase "hello")
if [[ "$result" == "HELLO" ]]; then
    kt_test_pass "Upper case"
else
    kt_test_fail "Upper case (expected: 'HELLO', got: '$result')"
fi
