#!/bin/bash
# ToBoolean
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToBoolean" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: True
kt_test_start "To boolean true"
result=$(string.toBoolean "true")
if [[ "$result" == "true" ]]; then
    kt_test_pass "To boolean true"
else
    kt_test_fail "To boolean true (expected: true, got: '$result')"
fi

# Test 2: False
kt_test_start "To boolean false"
result=$(string.toBoolean "false")
if [[ "$result" == "false" ]]; then
    kt_test_pass "To boolean false"
else
    kt_test_fail "To boolean false (expected: false, got: '$result')"
fi
