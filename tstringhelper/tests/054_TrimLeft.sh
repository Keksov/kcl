#!/bin/bash
# TrimLeft
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "TrimLeft" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Trim left
kk_test_start "Trim left"
result=$(string.trimLeft "  hello")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "Trim left"
else
    kk_test_fail "Trim left (expected: 'hello', got: '$result')"
fi
