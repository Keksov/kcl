#!/bin/bash
# TrimRight
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "TrimRight" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Trim right
kt_test_start "Trim right"
result=$(string.trimRight "hello  ")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Trim right"
else
    kt_test_fail "Trim right (expected: 'hello', got: '$result')"
fi
