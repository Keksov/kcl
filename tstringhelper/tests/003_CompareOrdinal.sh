#!/bin/bash
# CompareOrdinal
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "CompareOrdinal" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Equal strings
kt_test_start "CompareOrdinal equal"
result=$(string.compareOrdinal "abc" "abc")
if [[ "$result" == "0" ]]; then
    kt_test_pass "CompareOrdinal equal"
else
    kt_test_fail "CompareOrdinal equal (expected: 0, got: '$result')"
fi

# Test 2: Different strings
kt_test_start "CompareOrdinal different"
result=$(string.compareOrdinal "abc" "def")
if [[ "$result" == "-1" ]]; then
    kt_test_pass "CompareOrdinal different"
else
    kt_test_fail "CompareOrdinal different (expected: -1, got: '$result')"
fi
