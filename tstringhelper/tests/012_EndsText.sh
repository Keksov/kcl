#!/bin/bash
# EndsText
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "EndsText" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Ends with
kt_test_start "Ends with"
result=$(string.endsText "world" "hello world")
if [[ "$result" == "true" ]]; then
    kt_test_pass "Ends with"
else
    kt_test_fail "Ends with (expected: true, got: '$result')"
fi

# Test 2: Does not end with
kt_test_start "Does not end with"
result=$(string.endsText "hello" "hello world")
if [[ "$result" == "false" ]]; then
    kt_test_pass "Does not end with"
else
    kt_test_fail "Does not end with (expected: false, got: '$result')"
fi
