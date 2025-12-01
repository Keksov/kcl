#!/bin/bash
# TrimLeft
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "TrimLeft" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Trim left
kt_test_start "Trim left"
result=$(string.trimLeft "  hello")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Trim left"
else
    kt_test_fail "Trim left (expected: 'hello', got: '$result')"
fi
