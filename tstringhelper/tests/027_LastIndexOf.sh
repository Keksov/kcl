#!/bin/bash
# LastIndexOf
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "LastIndexOf" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Find last character
kk_test_start "LastIndexOf - find last character"
result=$(string.lastIndexOf "hello world" "o")
if [[ "$result" == "7" ]]; then
    kk_test_pass "LastIndexOf - find last character"
else
    kk_test_fail "LastIndexOf - find last character (expected: 7, got: '$result')"
fi

# Test 2: Find last substring
kk_test_start "LastIndexOf - find last substring"
result=$(string.lastIndexOf "hello world hello" "hello")
if [[ "$result" == "12" ]]; then
    kk_test_pass "LastIndexOf - find last substring"
else
    kk_test_fail "LastIndexOf - find last substring (expected: 12, got: '$result')"
fi

# Test 3: Character not found
kk_test_start "LastIndexOf - character not found"
result=$(string.lastIndexOf "hello" "z")
if [[ "$result" == "-1" ]]; then
    kk_test_pass "LastIndexOf - character not found"
else
    kk_test_fail "LastIndexOf - character not found (expected: -1, got: '$result')"
fi

# Test 4: Only one occurrence
kk_test_start "LastIndexOf - only one occurrence"
result=$(string.lastIndexOf "hello" "h")
if [[ "$result" == "0" ]]; then
    kk_test_pass "LastIndexOf - only one occurrence"
else
    kk_test_fail "LastIndexOf - only one occurrence (expected: 0, got: '$result')"
fi

# Test 5: Character at start
kk_test_start "LastIndexOf - first char"
result=$(string.lastIndexOf "hello" "h")
if [[ "$result" == "0" ]]; then
    kk_test_pass "LastIndexOf - first char"
else
    kk_test_fail "LastIndexOf - first char (expected: 0, got: '$result')"
fi

# Test 6: With start index
kk_test_start "LastIndexOf - with start index"
result=$(string.lastIndexOf "hello world hello" "hello" 10)
if [[ "$result" == "12" || "$result" == "0" ]]; then
    kk_test_pass "LastIndexOf - with start index"
else
    kk_test_fail "LastIndexOf - with start index (expected: 12 or 0, got: '$result')"
fi

# Test 7: With start index and count
kk_test_start "LastIndexOf - start index and count"
result=$(string.lastIndexOf "hello world hello" "l" 8 5)
if [[ "$result" == "3" || "$result" == "9" ]]; then
    kk_test_pass "LastIndexOf - start index and count"
else
    kk_test_fail "LastIndexOf - start index and count (expected: 3 or 9, got: '$result')"
fi

# Test 8: Empty search string
kk_test_start "LastIndexOf - empty search"
result=$(string.lastIndexOf "hello" "")
if [[ "$result" == "5" || "$result" == "-1" ]]; then
    kk_test_pass "LastIndexOf - empty search"
else
    kk_test_fail "LastIndexOf - empty search (expected: 5 or -1, got: '$result')"
fi

# Test 9: Case sensitive
kk_test_start "LastIndexOf - case sensitive"
result=$(string.lastIndexOf "Hello World" "h")
if [[ "$result" == "-1" ]]; then
    kk_test_pass "LastIndexOf - case sensitive"
else
    kk_test_fail "LastIndexOf - case sensitive (expected: -1, got: '$result')"
fi

# Test 10: Multiple occurrences
kk_test_start "LastIndexOf - multiple occurrences"
result=$(string.lastIndexOf "aabbaa" "a")
if [[ "$result" == "5" ]]; then
    kk_test_pass "LastIndexOf - multiple occurrences"
else
    kk_test_fail "LastIndexOf - multiple occurrences (expected: 4, got: '$result')"
fi

# Test 11: Last position
kk_test_start "LastIndexOf - last position"
result=$(string.lastIndexOf "hello" "o")
if [[ "$result" == "4" ]]; then
    kk_test_pass "LastIndexOf - last position"
else
    kk_test_fail "LastIndexOf - last position (expected: 4, got: '$result')"
fi

# Test 12: Substring at end
kk_test_start "LastIndexOf - substring at end"
result=$(string.lastIndexOf "hello world" "world")
if [[ "$result" == "6" ]]; then
    kk_test_pass "LastIndexOf - substring at end"
else
    kk_test_fail "LastIndexOf - substring at end (expected: 6, got: '$result')"
fi
