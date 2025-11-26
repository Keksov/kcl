#!/bin/bash
# Substring
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Substring" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Substring from index
kk_test_start "Substring from index"
result=$(string.substring "hello world" 6)
if [[ "$result" == "world" ]]; then
    kk_test_pass "Substring from index"
else
    kk_test_fail "Substring from index (expected: 'world', got: '$result')"
fi

# Test 2: Substring with length
kk_test_start "Substring with length"
result=$(string.substring "hello world" 0 5)
if [[ "$result" == "hello" ]]; then
    kk_test_pass "Substring with length"
else
    kk_test_fail "Substring with length (expected: 'hello', got: '$result')"
fi

# Test 3: Substring beyond length
kk_test_start "Substring beyond length"
result=$(string.substring "hello" 3 10)
if [[ "$result" == "lo" ]]; then
    kk_test_pass "Substring beyond length"
else
    kk_test_fail "Substring beyond length (expected: 'lo', got: '$result')"
fi

# Test 4: Start index 0
kk_test_start "Start index 0"
result=$(string.substring "hello" 0)
if [[ "$result" == "hello" ]]; then
    kk_test_pass "Start index 0"
else
    kk_test_fail "Start index 0 (expected: 'hello', got: '$result')"
fi

# Test 5: Empty string
kk_test_start "Empty string substring"
result=$(string.substring "" 0)
if [[ "$result" == "" ]]; then
    kk_test_pass "Empty string substring"
else
    kk_test_fail "Empty string substring (expected: '', got: '$result')"
fi
