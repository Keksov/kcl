#!/bin/bash
# ToDouble
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToDouble" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert to double
kt_test_start "To double"
result=$(string.toDouble "3.14")
if [[ "$result" == "3.14" ]]; then
    kt_test_pass "To double"
else
    kt_test_fail "To double (expected: 3.14, got: '$result')"
fi
