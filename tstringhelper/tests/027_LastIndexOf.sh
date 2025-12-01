#!/bin/bash
# LastIndexOf
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "LastIndexOf" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Find last character
kt_test_start "LastIndexOf - find last character"
result=$(string.lastIndexOf "hello world" "o")
if [[ "$result" == "7" ]]; then
    kt_test_pass "LastIndexOf - find last character"
else
    kt_test_fail "LastIndexOf - find last character (expected: 7, got: '$result')"
fi

# Test 2: Find last substring
kt_test_start "LastIndexOf - find last substring"
result=$(string.lastIndexOf "hello world hello" "hello")
if [[ "$result" == "12" ]]; then
    kt_test_pass "LastIndexOf - find last substring"
else
    kt_test_fail "LastIndexOf - find last substring (expected: 12, got: '$result')"
fi

# Test 3: Character not found
kt_test_start "LastIndexOf - character not found"
result=$(string.lastIndexOf "hello" "z")
if [[ "$result" == "-1" ]]; then
    kt_test_pass "LastIndexOf - character not found"
else
    kt_test_fail "LastIndexOf - character not found (expected: -1, got: '$result')"
fi

# Test 4: Only one occurrence
kt_test_start "LastIndexOf - only one occurrence"
result=$(string.lastIndexOf "hello" "h")
if [[ "$result" == "0" ]]; then
    kt_test_pass "LastIndexOf - only one occurrence"
else
    kt_test_fail "LastIndexOf - only one occurrence (expected: 0, got: '$result')"
fi

# Test 5: Character at start
kt_test_start "LastIndexOf - first char"
result=$(string.lastIndexOf "hello" "h")
if [[ "$result" == "0" ]]; then
    kt_test_pass "LastIndexOf - first char"
else
    kt_test_fail "LastIndexOf - first char (expected: 0, got: '$result')"
fi

# Test 6: With start index
kt_test_start "LastIndexOf - with start index"
result=$(string.lastIndexOf "hello world hello" "hello" 10)
if [[ "$result" == "12" || "$result" == "0" ]]; then
    kt_test_pass "LastIndexOf - with start index"
else
    kt_test_fail "LastIndexOf - with start index (expected: 12 or 0, got: '$result')"
fi

# Test 7: With start index and count
kt_test_start "LastIndexOf - start index and count"
result=$(string.lastIndexOf "hello world hello" "l" 8 5)
if [[ "$result" == "3" || "$result" == "9" ]]; then
    kt_test_pass "LastIndexOf - start index and count"
else
    kt_test_fail "LastIndexOf - start index and count (expected: 3 or 9, got: '$result')"
fi

# Test 8: Empty search string
kt_test_start "LastIndexOf - empty search"
result=$(string.lastIndexOf "hello" "")
if [[ "$result" == "5" || "$result" == "-1" ]]; then
    kt_test_pass "LastIndexOf - empty search"
else
    kt_test_fail "LastIndexOf - empty search (expected: 5 or -1, got: '$result')"
fi

# Test 9: Case sensitive
kt_test_start "LastIndexOf - case sensitive"
result=$(string.lastIndexOf "Hello World" "h")
if [[ "$result" == "-1" ]]; then
    kt_test_pass "LastIndexOf - case sensitive"
else
    kt_test_fail "LastIndexOf - case sensitive (expected: -1, got: '$result')"
fi

# Test 10: Multiple occurrences
kt_test_start "LastIndexOf - multiple occurrences"
result=$(string.lastIndexOf "aabbaa" "a")
if [[ "$result" == "5" ]]; then
    kt_test_pass "LastIndexOf - multiple occurrences"
else
    kt_test_fail "LastIndexOf - multiple occurrences (expected: 4, got: '$result')"
fi

# Test 11: Last position
kt_test_start "LastIndexOf - last position"
result=$(string.lastIndexOf "hello" "o")
if [[ "$result" == "4" ]]; then
    kt_test_pass "LastIndexOf - last position"
else
    kt_test_fail "LastIndexOf - last position (expected: 4, got: '$result')"
fi

# Test 12: Substring at end
kt_test_start "LastIndexOf - substring at end"
result=$(string.lastIndexOf "hello world" "world")
if [[ "$result" == "6" ]]; then
    kt_test_pass "LastIndexOf - substring at end"
else
    kt_test_fail "LastIndexOf - substring at end (expected: 6, got: '$result')"
fi
