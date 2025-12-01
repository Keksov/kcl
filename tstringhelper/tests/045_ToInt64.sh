#!/bin/bash
# ToInt64
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToInt64" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert to int
kt_test_start "To int64"
result=$(string.toInt64 "42")
if [[ "$result" == "42" ]]; then
    kt_test_pass "To int64"
else
    kt_test_fail "To int64 (expected: 42, got: '$result')"
fi
