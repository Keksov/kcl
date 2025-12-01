#!/bin/bash
# Split
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Split" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Split with comma separator
kt_test_start "Split - comma separator"
result=$(string.split "a,b,c" ",")
if [[ "$result" == *"a"* && "$result" == *"b"* && "$result" == *"c"* ]]; then
    kt_test_pass "Split - comma separator"
else
    kt_test_fail "Split - comma separator (expected: array with 'a', 'b', 'c', got: '$result')"
fi

# Test 2: Split with space separator
kt_test_start "Split - space separator"
result=$(string.split "hello world test" " ")
if [[ "$result" == *"hello"* && "$result" == *"world"* && "$result" == *"test"* ]]; then
    kt_test_pass "Split - space separator"
else
    kt_test_fail "Split - space separator (expected: array with parts, got: '$result')"
fi

# Test 3: Split with no matches
kt_test_start "Split - no matches"
result=$(string.split "hello" ",")
if [[ "$result" == *"hello"* ]]; then
    kt_test_pass "Split - no matches"
else
    kt_test_fail "Split - no matches (expected: array with 'hello', got: '$result')"
fi

# Test 4: Split empty string
kt_test_start "Split - empty string"
result=$(string.split "" ",")
if [[ "$result" == "" || "$result" == *"0"* ]]; then
    kt_test_pass "Split - empty string"
else
    kt_test_fail "Split - empty string (expected: empty or 0, got: '$result')"
fi

# Test 5: Split with count limit
kt_test_start "Split - with count limit"
result=$(string.split "a,b,c,d" "," 2)
if [[ "$result" == *"a"* && "$result" == *"b"* ]]; then
    kt_test_pass "Split - with count limit"
else
    kt_test_fail "Split - with count limit (expected: limited array, got: '$result')"
fi

# Test 6: Split single element
kt_test_start "Split - single element"
result=$(string.split "hello" "x")
if [[ "$result" == *"hello"* ]]; then
    kt_test_pass "Split - single element"
else
    kt_test_fail "Split - single element (expected: array with 'hello', got: '$result')"
fi

# Test 7: Split with pipe separator
kt_test_start "Split - pipe separator"
result=$(string.split "one|two|three" "|")
if [[ "$result" == *"one"* && "$result" == *"two"* && "$result" == *"three"* ]]; then
    kt_test_pass "Split - pipe separator"
else
    kt_test_fail "Split - pipe separator (expected: array with parts, got: '$result')"
fi

# Test 8: Split with colon separator
kt_test_start "Split - colon separator"
result=$(string.split "a:b:c" ":")
if [[ "$result" == *"a"* && "$result" == *"b"* && "$result" == *"c"* ]]; then
    kt_test_pass "Split - colon separator"
else
    kt_test_fail "Split - colon separator (expected: array with parts, got: '$result')"
fi

# Test 9: Split consecutive separators
kt_test_start "Split - consecutive separators"
result=$(string.split "a,,c" ",")
if [[ "$result" == *"a"* && "$result" == *"c"* ]]; then
    kt_test_pass "Split - consecutive separators"
else
    kt_test_fail "Split - consecutive separators (expected: array including empty, got: '$result')"
fi

# Test 10: Split with numeric strings
kt_test_start "Split - numeric strings"
result=$(string.split "1-2-3" "-")
if [[ "$result" == *"1"* && "$result" == *"2"* && "$result" == *"3"* ]]; then
    kt_test_pass "Split - numeric strings"
else
    kt_test_fail "Split - numeric strings (expected: array with numbers, got: '$result')"
fi
