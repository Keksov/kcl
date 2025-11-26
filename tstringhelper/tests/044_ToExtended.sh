#!/bin/bash
# ToExtended
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "ToExtended" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: To extended
kk_test_start "To extended"
result=$(string.toDouble "3.14")  # reusing
if [[ "$result" == "3.14" ]]; then
    kk_test_pass "To extended"
else
    kk_test_fail "To extended (expected: 3.14, got: '$result')"
fi
