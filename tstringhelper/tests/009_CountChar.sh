#!/bin/bash
# CountChar
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "CountChar" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Count occurrences
kt_test_start "Count char"
result=$(string.countChar "hello world" "l")
if [[ "$result" == "3" ]]; then
    kt_test_pass "Count char"
else
    kt_test_fail "Count char (expected: 3, got: '$result')"
fi

# Test 2: No occurrences
kt_test_start "No occurrences"
result=$(string.countChar "hello" "z")
if [[ "$result" == "0" ]]; then
    kt_test_pass "No occurrences"
else
    kt_test_fail "No occurrences (expected: 0, got: '$result')"
fi
