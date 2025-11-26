#!/bin/bash
# ToBoolean
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "ToBoolean" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: True
kk_test_start "To boolean true"
result=$(string.toBoolean "true")
if [[ "$result" == "true" ]]; then
    kk_test_pass "To boolean true"
else
    kk_test_fail "To boolean true (expected: true, got: '$result')"
fi

# Test 2: False
kk_test_start "To boolean false"
result=$(string.toBoolean "false")
if [[ "$result" == "false" ]]; then
    kk_test_pass "To boolean false"
else
    kk_test_fail "To boolean false (expected: false, got: '$result')"
fi
