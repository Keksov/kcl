#!/bin/bash
# ToCharArray
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "ToCharArray" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: To char array
kk_test_start "To char array"
result=$(string.toCharArray "hi")
# Expected output not defined, just check it runs
if [[ -n "$result" ]]; then
    kk_test_pass "To char array"
else
    kk_test_fail "To char array"
fi
