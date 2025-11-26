#!/bin/bash
# ToDouble
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "ToDouble" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert to double
kk_test_start "To double"
result=$(string.toDouble "3.14")
if [[ "$result" == "3.14" ]]; then
    kk_test_pass "To double"
else
    kk_test_fail "To double (expected: 3.14, got: '$result')"
fi
