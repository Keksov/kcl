#!/bin/bash
# ToLower
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToLower" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert to lowercase
kt_test_start "To lower case"
result=$(string.toLower "HELLO WORLD")
if [[ "$result" == "hello world" ]]; then
    kt_test_pass "To lower case"
else
    kt_test_fail "To lower case (expected: 'hello world', got: '$result')"
fi

# Test 2: Already lowercase
kt_test_start "Already lowercase"
result=$(string.toLower "hello")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Already lowercase"
else
    kt_test_fail "Already lowercase (expected: 'hello', got: '$result')"
fi

# Test 3: Mixed case
kt_test_start "Mixed case"
result=$(string.toLower "HeLLo WoRlD")
if [[ "$result" == "hello world" ]]; then
    kt_test_pass "Mixed case"
else
    kt_test_fail "Mixed case (expected: 'hello world', got: '$result')"
fi

# Test 4: Empty string
kt_test_start "Empty string"
result=$(string.toLower "")
if [[ "$result" == "" ]]; then
    kt_test_pass "Empty string"
else
    kt_test_fail "Empty string (expected: '', got: '$result')"
fi
