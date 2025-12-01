#!/bin/bash
# ToUpper
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToUpper" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert to uppercase
kt_test_start "To upper case"
result=$(string.toUpper "hello world")
if [[ "$result" == "HELLO WORLD" ]]; then
    kt_test_pass "To upper case"
else
    kt_test_fail "To upper case (expected: 'HELLO WORLD', got: '$result')"
fi

# Test 2: Already uppercase
kt_test_start "Already uppercase"
result=$(string.toUpper "HELLO")
if [[ "$result" == "HELLO" ]]; then
    kt_test_pass "Already uppercase"
else
    kt_test_fail "Already uppercase (expected: 'HELLO', got: '$result')"
fi

# Test 3: Mixed case
kt_test_start "Mixed case"
result=$(string.toUpper "HeLLo WoRlD")
if [[ "$result" == "HELLO WORLD" ]]; then
    kt_test_pass "Mixed case"
else
    kt_test_fail "Mixed case (expected: 'HELLO WORLD', got: '$result')"
fi

# Test 4: Empty string
kt_test_start "Empty string"
result=$(string.toUpper "")
if [[ "$result" == "" ]]; then
    kt_test_pass "Empty string"
else
    kt_test_fail "Empty string (expected: '', got: '$result')"
fi
