#!/bin/bash
# CompareTo
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "CompareTo" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Equal
kk_test_start "CompareTo equal"
result=$(string.compareTo "test" "test")
if [[ "$result" == "0" ]]; then
    kk_test_pass "CompareTo equal"
else
    kk_test_fail "CompareTo equal (expected: 0, got: '$result')"
fi

# Test 2: Less
kk_test_start "CompareTo less"
result=$(string.compareTo "abc" "def")
if [[ "$result" == "-1" ]]; then
    kk_test_pass "CompareTo less"
else
    kk_test_fail "CompareTo less (expected: -1, got: '$result')"
fi
