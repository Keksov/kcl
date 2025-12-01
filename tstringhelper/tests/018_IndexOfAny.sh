#!/bin/bash
# IndexOfAny
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "IndexOfAny" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Find first character from array
kt_test_start "IndexOfAny - find first matching character"
result=$(string.indexOfAny "hello world" "w")
if [[ "$result" == "6" ]]; then
    kt_test_pass "IndexOfAny - find first matching character"
else
    kt_test_fail "IndexOfAny - find first matching character (expected: 6, got: '$result')"
fi

# Test 2: Find first of multiple characters
kt_test_start "IndexOfAny - multiple characters"
result=$(string.indexOfAny "hello world" "owx")
if [[ "$result" == "4" ]]; then
    kt_test_pass "IndexOfAny - multiple characters"
else
    kt_test_fail "IndexOfAny - multiple characters (expected: 4, got: '$result')"
fi

# Test 3: No matching character
kt_test_start "IndexOfAny - no match"
result=$(string.indexOfAny "hello" "xyz")
if [[ "$result" == "-1" ]]; then
    kt_test_pass "IndexOfAny - no match"
else
    kt_test_fail "IndexOfAny - no match (expected: -1, got: '$result')"
fi

# Test 4: Match at start
kt_test_start "IndexOfAny - match at start"
result=$(string.indexOfAny "hello" "he")
if [[ "$result" == "0" ]]; then
    kt_test_pass "IndexOfAny - match at start"
else
    kt_test_fail "IndexOfAny - match at start (expected: 0, got: '$result')"
fi

# Test 5: Match at end
kt_test_start "IndexOfAny - match at end"
result=$(string.indexOfAny "hello" "o")
if [[ "$result" == "4" ]]; then
    kt_test_pass "IndexOfAny - match at end"
else
    kt_test_fail "IndexOfAny - match at end (expected: 4, got: '$result')"
fi

# Test 6: With start index
kt_test_start "IndexOfAny - with start index"
result=$(string.indexOfAny "hello world" "aeiou" 5)
if [[ "$result" == "7" ]]; then
    kt_test_pass "IndexOfAny - with start index"
else
    kt_test_fail "IndexOfAny - with start index (expected: 7, got: '$result')"
fi

# Test 7: With start index and count
kt_test_start "IndexOfAny - start index and count"
result=$(string.indexOfAny "This is a string" "is" 9 4)
if [[ "$result" == "10" || "$result" == "13" ]]; then
    kt_test_pass "IndexOfAny - start index and count"
else
    kt_test_fail "IndexOfAny - start index and count (expected: 10 or 13, got: '$result')"
fi

# Test 8: Empty character array
kt_test_start "IndexOfAny - empty array"
result=$(string.indexOfAny "hello" "")
if [[ "$result" == "-1" ]]; then
    kt_test_pass "IndexOfAny - empty array"
else
    kt_test_fail "IndexOfAny - empty array (expected: -1, got: '$result')"
fi

# Test 9: Single character from multiple
kt_test_start "IndexOfAny - single match from multiple"
result=$(string.indexOfAny "hello world" "ws")
if [[ "$result" == "6" ]]; then
    kt_test_pass "IndexOfAny - single match from multiple"
else
    kt_test_fail "IndexOfAny - single match from multiple (expected: 6, got: '$result')"
fi

# Test 10: Case sensitive search
kt_test_start "IndexOfAny - case sensitive"
result=$(string.indexOfAny "Hello World" "w")
if [[ "$result" == "-1" ]]; then
    kt_test_pass "IndexOfAny - case sensitive"
else
    kt_test_fail "IndexOfAny - case sensitive (expected: -1, got: '$result')"
fi

# Test 11: Invalid start index
kt_test_start "IndexOfAny - invalid start index"
result=$(string.indexOfAny "hello" "aeiou" 20)
if [[ "$result" == "-1" ]]; then
    kt_test_pass "IndexOfAny - invalid start index"
else
    kt_test_fail "IndexOfAny - invalid start index (expected: -1, got: '$result')"
fi

# Test 12: Count larger than remaining string
kt_test_start "IndexOfAny - count larger than remaining"
result=$(string.indexOfAny "hello" "h" 0 100)
if [[ "$result" == "0" ]]; then
    kt_test_pass "IndexOfAny - count larger than remaining"
else
    kt_test_fail "IndexOfAny - count larger than remaining (expected: 0, got: '$result')"
fi
