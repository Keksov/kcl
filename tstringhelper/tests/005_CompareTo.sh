#!/bin/bash
# CompareTo
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "CompareTo" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Equal
kt_test_start "CompareTo equal"
result=$(string.compareTo "test" "test")
if [[ "$result" == "0" ]]; then
    kt_test_pass "CompareTo equal"
else
    kt_test_fail "CompareTo equal (expected: 0, got: '$result')"
fi

# Test 2: Less
kt_test_start "CompareTo less"
result=$(string.compareTo "abc" "def")
if [[ "$result" == "-1" ]]; then
    kt_test_pass "CompareTo less"
else
    kt_test_fail "CompareTo less (expected: -1, got: '$result')"
fi
