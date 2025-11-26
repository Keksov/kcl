#!/bin/bash
# CompareText
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "CompareText" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Case insensitive equal
kk_test_start "CompareText equal ignore case"
result=$(string.compareText "Hello" "HELLO")
if [[ "$result" == "0" ]]; then
    kk_test_pass "CompareText equal ignore case"
else
    kk_test_fail "CompareText equal ignore case (expected: 0, got: '$result')"
fi

# Test 2: Different case
kk_test_start "CompareText different"
result=$(string.compareText "abc" "DEF")
if [[ "$result" == "-1" ]]; then
    kk_test_pass "CompareText different"
else
    kk_test_fail "CompareText different (expected: -1, got: '$result')"
fi
