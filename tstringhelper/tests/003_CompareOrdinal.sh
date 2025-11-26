#!/bin/bash
# CompareOrdinal
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "CompareOrdinal" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Equal strings
kk_test_start "CompareOrdinal equal"
result=$(string.compareOrdinal "abc" "abc")
if [[ "$result" == "0" ]]; then
    kk_test_pass "CompareOrdinal equal"
else
    kk_test_fail "CompareOrdinal equal (expected: 0, got: '$result')"
fi

# Test 2: Different strings
kk_test_start "CompareOrdinal different"
result=$(string.compareOrdinal "abc" "def")
if [[ "$result" == "-1" ]]; then
    kk_test_pass "CompareOrdinal different"
else
    kk_test_fail "CompareOrdinal different (expected: -1, got: '$result')"
fi
