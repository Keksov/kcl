#!/bin/bash
# Length
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Length" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Length of non-empty string
kk_test_start "Length of string"
result=$(string.length "hello")
if [[ "$result" == "5" ]]; then
    kk_test_pass "Length of string"
else
    kk_test_fail "Length of string (expected: 5, got: '$result')"
fi

# Test 2: Length of empty string
kk_test_start "Length of empty string"
result=$(string.length "")
if [[ "$result" == "0" ]]; then
    kk_test_pass "Length of empty string"
else
    kk_test_fail "Length of empty string (expected: 0, got: '$result')"
fi

# Test 3: Length with spaces
kk_test_start "Length with spaces"
result=$(string.length "hello world")
if [[ "$result" == "11" ]]; then
    kk_test_pass "Length with spaces"
else
    kk_test_fail "Length with spaces (expected: 11, got: '$result')"
fi
