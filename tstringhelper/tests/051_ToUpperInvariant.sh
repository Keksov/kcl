#!/bin/bash
# ToUpperInvariant
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "ToUpperInvariant" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: To upper invariant
kk_test_start "To upper invariant"
result=$(string.toUpperInvariant "hello")
if [[ "$result" == "HELLO" ]]; then
    kk_test_pass "To upper invariant"
else
    kk_test_fail "To upper invariant (expected: 'HELLO', got: '$result')"
fi
