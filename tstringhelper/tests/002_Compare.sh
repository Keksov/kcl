#!/bin/bash
# Compare
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Compare" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Equal strings
kt_test_start "Compare equal strings"
result=$(string.compare "hello" "hello")
if [[ "$result" == "0" ]]; then
    kt_test_pass "Compare equal strings"
else
    kt_test_fail "Compare equal strings (expected: 0, got: '$result')"
fi

# Test 2: First string less than second
kt_test_start "Compare strA < strB"
result=$(string.compare "apple" "banana")
if [[ "$result" == "-1" ]]; then
    kt_test_pass "Compare strA < strB"
else
    kt_test_fail "Compare strA < strB (expected: -1, got: '$result')"
fi

# Test 3: First string greater than second
kt_test_start "Compare strA > strB"
result=$(string.compare "zebra" "apple")
if [[ "$result" == "1" ]]; then
    kt_test_pass "Compare strA > strB"
else
    kt_test_fail "Compare strA > strB (expected: 1, got: '$result')"
fi

# Test 4: Empty strings
kt_test_start "Compare empty strings"
result=$(string.compare "" "")
if [[ "$result" == "0" ]]; then
    kt_test_pass "Compare empty strings"
else
    kt_test_fail "Compare empty strings (expected: 0, got: '$result')"
fi

# Test 5: One empty string
kt_test_start "Compare empty and non-empty"
result=$(string.compare "" "test")
if [[ "$result" == "-1" ]]; then
    kt_test_pass "Compare empty and non-empty"
else
    kt_test_fail "Compare empty and non-empty (expected: -1, got: '$result')"
fi
