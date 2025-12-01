#!/bin/bash
# ToUpperInvariant
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToUpperInvariant" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: To upper invariant
kt_test_start "To upper invariant"
result=$(string.toUpperInvariant "hello")
if [[ "$result" == "HELLO" ]]; then
    kt_test_pass "To upper invariant"
else
    kt_test_fail "To upper invariant (expected: 'HELLO', got: '$result')"
fi
