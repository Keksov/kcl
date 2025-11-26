#!/bin/bash
# ToLower
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "ToLower" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert to lowercase
kk_test_start "To lower case"
result=$(string.toLower "HELLO WORLD")
if [[ "$result" == "hello world" ]]; then
    kk_test_pass "To lower case"
else
    kk_test_fail "To lower case (expected: 'hello world', got: '$result')"
fi

# Test 2: Already lowercase
kk_test_start "Already lowercase"
result=$(string.toLower "hello")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "Already lowercase"
else
    kk_test_fail "Already lowercase (expected: 'hello', got: '$result')"
fi

# Test 3: Mixed case
kk_test_start "Mixed case"
result=$(string.toLower "HeLLo WoRlD")
if [[ "$result" == "hello world" ]]; then
    kk_test_pass "Mixed case"
else
    kk_test_fail "Mixed case (expected: 'hello world', got: '$result')"
fi

# Test 4: Empty string
kk_test_start "Empty string"
result=$(string.toLower "")
if [[ "$result" == "" ]]; then
    kk_test_pass "Empty string"
else
    kk_test_fail "Empty string (expected: '', got: '$result')"
fi
