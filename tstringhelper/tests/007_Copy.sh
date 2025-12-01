#!/bin/bash
# Copy
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Copy" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Copy string
kt_test_start "Copy string"
result=$(string.copy "hello")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Copy string"
else
    kt_test_fail "Copy string (expected: 'hello', got: '$result')"
fi
