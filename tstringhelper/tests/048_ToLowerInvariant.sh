#!/bin/bash
# ToLowerInvariant
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "ToLowerInvariant" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: To lower invariant
kk_test_start "To lower invariant"
result=$(string.toLowerInvariant "HELLO")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "To lower invariant"
else
    kk_test_fail "To lower invariant (expected: 'hello', got: '$result')"
fi
