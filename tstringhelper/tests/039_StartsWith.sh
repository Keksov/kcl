#!/bin/bash
# StartsWith
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "StartsWith" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Starts with
kt_test_start "Starts with"
result=$(string.startsWith "hello world" "hello")
if [[ "$result" == "true" ]]; then
    kt_test_pass "Starts with"
else
    kt_test_fail "Starts with (expected: true, got: '$result')"
fi

# Test 2: Does not start with
kt_test_start "Does not start with"
result=$(string.startsWith "hello world" "world")
if [[ "$result" == "false" ]]; then
    kt_test_pass "Does not start with"
else
    kt_test_fail "Does not start with (expected: false, got: '$result')"
fi
