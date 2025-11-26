#!/bin/bash
# ToSingle
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "ToSingle" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: To single
kk_test_start "To single"
result=$(string.toSingle "2.5")
if [[ "$result" == "2.5" ]]; then
    kk_test_pass "To single"
else
    kk_test_fail "To single (expected: 2.5, got: '$result')"
fi
