#!/bin/bash
# ToSingle
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToSingle" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: To single
kt_test_start "To single"
result=$(string.toSingle "2.5")
if [[ "$result" == "2.5" ]]; then
    kt_test_pass "To single"
else
    kt_test_fail "To single (expected: 2.5, got: '$result')"
fi
