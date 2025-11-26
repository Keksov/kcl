#!/bin/bash
# LastIndexOfAny
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "LastIndexOfAny" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Find last of matching characters
kk_test_start "LastIndexOfAny - find last matching"
result=$(string.lastIndexOfAny "hello world" "aeiou")
if [[ "$result" == "7" ]]; then
    kk_test_pass "LastIndexOfAny - find last matching"
else
    kk_test_fail "LastIndexOfAny - find last matching (expected: 7, got: '$result')"
fi

# Test 2: No matching characters
kk_test_start "LastIndexOfAny - no match"
result=$(string.lastIndexOfAny "hello" "xyz")
if [[ "$result" == "-1" ]]; then
    kk_test_pass "LastIndexOfAny - no match"
else
    kk_test_fail "LastIndexOfAny - no match (expected: -1, got: '$result')"
fi

# Test 3: Single character array
kk_test_start "LastIndexOfAny - single character"
result=$(string.lastIndexOfAny "hello" "o")
if [[ "$result" == "4" ]]; then
    kk_test_pass "LastIndexOfAny - single character"
else
    kk_test_fail "LastIndexOfAny - single character (expected: 4, got: '$result')"
fi

# Test 4: Multiple matching characters
kk_test_start "LastIndexOfAny - multiple matches"
result=$(string.lastIndexOfAny "aabbcc" "bc")
if [[ "$result" == "5" ]]; then
    kk_test_pass "LastIndexOfAny - multiple matches"
else
    kk_test_fail "LastIndexOfAny - multiple matches (expected: 5, got: '$result')"
fi

# Test 5: Character at end
kk_test_start "LastIndexOfAny - character at end"
result=$(string.lastIndexOfAny "hello" "o")
if [[ "$result" == "4" ]]; then
    kk_test_pass "LastIndexOfAny - character at end"
else
    kk_test_fail "LastIndexOfAny - character at end (expected: 4, got: '$result')"
fi

# Test 6: Character at start
kk_test_start "LastIndexOfAny - character at start"
result=$(string.lastIndexOfAny "hello" "h")
if [[ "$result" == "0" ]]; then
    kk_test_pass "LastIndexOfAny - character at start"
else
    kk_test_fail "LastIndexOfAny - character at start (expected: 0, got: '$result')"
fi

# Test 7: With start index
kk_test_start "LastIndexOfAny - with start index"
result=$(string.lastIndexOfAny "hello world" "aeiou" 5)
if [[ "$result" == "4" || "$result" == "7" ]]; then
    kk_test_pass "LastIndexOfAny - with start index"
else
    kk_test_fail "LastIndexOfAny - with start index (expected: 4 or 7, got: '$result')"
fi

# Test 8: With start index and count
kk_test_start "LastIndexOfAny - start and count"
result=$(string.lastIndexOfAny "hello world" "aeiou" 5 5)
if [[ "$result" == "4" || "$result" == "-1" ]]; then
    kk_test_pass "LastIndexOfAny - start and count"
else
    kk_test_fail "LastIndexOfAny - start and count (expected: 4 or -1, got: '$result')"
fi

# Test 9: Vowels in string
kk_test_start "LastIndexOfAny - vowels"
result=$(string.lastIndexOfAny "beautiful" "aeiou")
if [[ "$result" == "7" ]]; then
    kk_test_pass "LastIndexOfAny - vowels"
else
    kk_test_fail "LastIndexOfAny - vowels (expected: 7, got: '$result')"
fi

# Test 10: Case sensitive
kk_test_start "LastIndexOfAny - case sensitive"
result=$(string.lastIndexOfAny "Hello" "aeiou")
if [[ "$result" == "4" ]]; then
    kk_test_pass "LastIndexOfAny - case sensitive"
else
    kk_test_fail "LastIndexOfAny - case sensitive (expected: -1, got: '$result')"
fi

# Test 11: Empty array
kk_test_start "LastIndexOfAny - empty array"
result=$(string.lastIndexOfAny "hello" "")
if [[ "$result" == "-1" ]]; then
    kk_test_pass "LastIndexOfAny - empty array"
else
    kk_test_fail "LastIndexOfAny - empty array (expected: -1, got: '$result')"
fi

# Test 12: All characters match
kk_test_start "LastIndexOfAny - all match"
result=$(string.lastIndexOfAny "aaa" "a")
if [[ "$result" == "2" ]]; then
    kk_test_pass "LastIndexOfAny - all match"
else
    kk_test_fail "LastIndexOfAny - all match (expected: 2, got: '$result')"
fi
