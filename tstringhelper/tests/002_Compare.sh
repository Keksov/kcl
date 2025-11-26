#!/bin/bash
# Compare
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Compare" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Equal strings
kk_test_start "Compare equal strings"
result=$(string.compare "hello" "hello")
if [[ "$result" == "0" ]]; then
    kk_test_pass "Compare equal strings"
else
    kk_test_fail "Compare equal strings (expected: 0, got: '$result')"
fi

# Test 2: First string less than second
kk_test_start "Compare strA < strB"
result=$(string.compare "apple" "banana")
if [[ "$result" == "-1" ]]; then
    kk_test_pass "Compare strA < strB"
else
    kk_test_fail "Compare strA < strB (expected: -1, got: '$result')"
fi

# Test 3: First string greater than second
kk_test_start "Compare strA > strB"
result=$(string.compare "zebra" "apple")
if [[ "$result" == "1" ]]; then
    kk_test_pass "Compare strA > strB"
else
    kk_test_fail "Compare strA > strB (expected: 1, got: '$result')"
fi

# Test 4: Empty strings
kk_test_start "Compare empty strings"
result=$(string.compare "" "")
if [[ "$result" == "0" ]]; then
    kk_test_pass "Compare empty strings"
else
    kk_test_fail "Compare empty strings (expected: 0, got: '$result')"
fi

# Test 5: One empty string
kk_test_start "Compare empty and non-empty"
result=$(string.compare "" "test")
if [[ "$result" == "-1" ]]; then
    kk_test_pass "Compare empty and non-empty"
else
    kk_test_fail "Compare empty and non-empty (expected: -1, got: '$result')"
fi
