#!/bin/bash
# Chars
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Chars" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Get char at index
kk_test_start "Get char at index"
result=$(string.chars "hello" 0)
if [[ "$result" == "h" ]]; then
    kk_test_pass "Get char at index"
else
    kk_test_fail "Get char at index (expected: 'h', got: '$result')"
fi

# Test 2: Invalid index
kk_test_start "Invalid index"
result=$(string.chars "hello" 10)
if [[ "$result" == "undefined" ]]; then
    kk_test_pass "Invalid index"
else
    kk_test_fail "Invalid index (expected: 'undefined', got: '$result')"
fi
