#!/bin/bash
# EndsText
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "EndsText" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Ends with
kk_test_start "Ends with"
result=$(string.endsText "world" "hello world")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Ends with"
else
    kk_test_fail "Ends with (expected: true, got: '$result')"
fi

# Test 2: Does not end with
kk_test_start "Does not end with"
result=$(string.endsText "hello" "hello world")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Does not end with"
else
    kk_test_fail "Does not end with (expected: false, got: '$result')"
fi
