#!/bin/bash
# ToExtended
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToExtended" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: To extended
kt_test_start "To extended"
result=$(string.toDouble "3.14")  # reusing
if [[ "$result" == "3.14" ]]; then
    kt_test_pass "To extended"
else
    kt_test_fail "To extended (expected: 3.14, got: '$result')"
fi
