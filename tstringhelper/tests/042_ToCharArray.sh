#!/bin/bash
# ToCharArray
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToCharArray" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: To char array
kt_test_start "To char array"
result=$(string.toCharArray "hi")
# Expected output not defined, just check it runs
if [[ -n "$result" ]]; then
    kt_test_pass "To char array"
else
    kt_test_fail "To char array"
fi
