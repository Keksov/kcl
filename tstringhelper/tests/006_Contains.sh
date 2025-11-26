#!/bin/bash
# Contains
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Contains" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: String contains substring
kk_test_start "Contains substring"
result=$(string.contains "hello world" "world")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Contains substring"
else
    kk_test_fail "Contains substring (expected: true, got: '$result')"
fi

# Test 2: String does not contain substring
kk_test_start "Does not contain substring"
result=$(string.contains "hello world" "test")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Does not contain substring"
else
    kk_test_fail "Does not contain substring (expected: false, got: '$result')"
fi

# Test 3: Empty substring
kk_test_start "Contains empty string"
result=$(string.contains "hello" "")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Contains empty string"
else
    kk_test_fail "Contains empty string (expected: true, got: '$result')"
fi

# Test 4: Substring at start
kk_test_start "Contains at start"
result=$(string.contains "hello world" "hello")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Contains at start"
else
    kk_test_fail "Contains at start (expected: true, got: '$result')"
fi

# Test 5: Substring at end
kk_test_start "Contains at end"
result=$(string.contains "hello world" "world")
if [[ "$result" == "true" ]]; then
    kk_test_pass "Contains at end"
else
    kk_test_fail "Contains at end (expected: true, got: '$result')"
fi

# Test 6: Case sensitivity
kk_test_start "Case sensitive contains"
result=$(string.contains "Hello World" "hello")
if [[ "$result" == "false" ]]; then
    kk_test_pass "Case sensitive contains"
else
    kk_test_fail "Case sensitive contains (expected: false, got: '$result')"
fi
