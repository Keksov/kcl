#!/bin/bash
# ToLowerInvariant
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToLowerInvariant" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: To lower invariant
kt_test_start "To lower invariant"
result=$(string.toLowerInvariant "HELLO")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "To lower invariant"
else
    kt_test_fail "To lower invariant (expected: 'hello', got: '$result')"
fi
