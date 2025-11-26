#!/bin/bash
# ToUpper
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "ToUpper" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert to uppercase
kk_test_start "To upper case"
result=$(string.toUpper "hello world")
if [[ "$result" == "HELLO WORLD" ]]; then
    kk_test_pass "To upper case"
else
    kk_test_fail "To upper case (expected: 'HELLO WORLD', got: '$result')"
fi

# Test 2: Already uppercase
kk_test_start "Already uppercase"
result=$(string.toUpper "HELLO")
if [[ "$result" == "HELLO" ]]; then
    kk_test_pass "Already uppercase"
else
    kk_test_fail "Already uppercase (expected: 'HELLO', got: '$result')"
fi

# Test 3: Mixed case
kk_test_start "Mixed case"
result=$(string.toUpper "HeLLo WoRlD")
if [[ "$result" == "HELLO WORLD" ]]; then
    kk_test_pass "Mixed case"
else
    kk_test_fail "Mixed case (expected: 'HELLO WORLD', got: '$result')"
fi

# Test 4: Empty string
kk_test_start "Empty string"
result=$(string.toUpper "")
if [[ "$result" == "" ]]; then
    kk_test_pass "Empty string"
else
    kk_test_fail "Empty string (expected: '', got: '$result')"
fi
