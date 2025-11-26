#!/bin/bash
# UpperCase
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "UpperCase" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Upper case
kk_test_start "Upper case"
result=$(string.upperCase "hello")
if [[ "$result" == "HELLO" ]]; then
    kk_test_pass "Upper case"
else
    kk_test_fail "Upper case (expected: 'HELLO', got: '$result')"
fi
