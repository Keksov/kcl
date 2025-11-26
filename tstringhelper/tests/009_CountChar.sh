#!/bin/bash
# CountChar
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "CountChar" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Count occurrences
kk_test_start "Count char"
result=$(string.countChar "hello world" "l")
if [[ "$result" == "3" ]]; then
    kk_test_pass "Count char"
else
    kk_test_fail "Count char (expected: 3, got: '$result')"
fi

# Test 2: No occurrences
kk_test_start "No occurrences"
result=$(string.countChar "hello" "z")
if [[ "$result" == "0" ]]; then
    kk_test_pass "No occurrences"
else
    kk_test_fail "No occurrences (expected: 0, got: '$result')"
fi
