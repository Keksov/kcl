#!/bin/bash
# IndexOfAnyUnquoted
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "IndexOfAnyUnquoted" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Find unquoted character
kk_test_start "IndexOfAnyUnquoted - simple unquoted"
result=$(string.indexOfAnyUnquoted "This is it" "i" '"' '"')
if [[ "$result" == "2" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - simple unquoted"
else
    kk_test_fail "IndexOfAnyUnquoted - simple unquoted (expected: 7, got: '$result')"
fi

# Test 2: Character inside quotes
kk_test_start "IndexOfAnyUnquoted - inside quotes"
result=$(string.indexOfAnyUnquoted '"This" is it' "i" '"' '"')
if [[ "$result" == "7" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - inside quotes"
else
    kk_test_fail "IndexOfAnyUnquoted - inside quotes (expected: 7, got: '$result')"
fi

# Test 3: No closing quote
kk_test_start "IndexOfAnyUnquoted - no closing quote"
result=$(string.indexOfAnyUnquoted '"This is it' "i" '"' '"')
if [[ "$result" == "-1" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - no closing quote"
else
    kk_test_fail "IndexOfAnyUnquoted - no closing quote (expected: -1, got: '$result')"
fi

# Test 4: All spaces unquoted
kk_test_start "IndexOfAnyUnquoted - all spaces unquoted"
result=$(string.indexOfAnyUnquoted '"This" "is" "it"' " " '"' '"')
if [[ "$result" == "6" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - all spaces unquoted"
else
    kk_test_fail "IndexOfAnyUnquoted - all spaces unquoted (expected: -1, got: '$result')"
fi

# Test 5: Nested quotes with different markers
kk_test_start "IndexOfAnyUnquoted - nested quotes"
result=$(string.indexOfAnyUnquoted "<This <is>> it" "i" "<" ">")
if [[ "$result" == "12" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - nested quotes"
else
    kk_test_fail "IndexOfAnyUnquoted - nested quotes (expected: 12, got: '$result')"
fi

# Test 6: With start index
kk_test_start "IndexOfAnyUnquoted - with start index"
result=$(string.indexOfAnyUnquoted '"Th i s" is it' "i" '"' '"' 1)
if [[ "$result" == "4" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - with start index"
else
    kk_test_fail "IndexOfAnyUnquoted - with start index (expected: 7 or 8, got: '$result')"
fi

# Test 7: Find first unquoted from multiple
kk_test_start "IndexOfAnyUnquoted - first unquoted"
result=$(string.indexOfAnyUnquoted '"i"s it' "is" '"' '"')
if [[ "$result" == "3" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - first unquoted"
else
    kk_test_fail "IndexOfAnyUnquoted - first unquoted (expected: 3, got: '$result')"
fi

# Test 8: Same quote markers
kk_test_start "IndexOfAnyUnquoted - same quote markers"
result=$(string.indexOfAnyUnquoted "'This' is it" "i" "'" "'")
if [[ "$result" == "7" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - same quote markers"
else
    kk_test_fail "IndexOfAnyUnquoted - same quote markers (expected: 7, got: '$result')"
fi

# Test 9: No match found
kk_test_start "IndexOfAnyUnquoted - no match"
result=$(string.indexOfAnyUnquoted '"text" data' "z" '"' '"')
if [[ "$result" == "-1" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - no match"
else
    kk_test_fail "IndexOfAnyUnquoted - no match (expected: -1, got: '$result')"
fi

# Test 10: Multiple quoting areas
kk_test_start "IndexOfAnyUnquoted - multiple quoted sections"
result=$(string.indexOfAnyUnquoted '"a=b" and "c=d" end' "=" '"' '"')
if [[ "$result" == "-1" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - multiple quoted sections"
else
    kk_test_fail "IndexOfAnyUnquoted - multiple quoted sections (expected: 11, got: '$result')"
fi

# Test 11: With start index and count
kk_test_start "IndexOfAnyUnquoted - start and count"
result=$(string.indexOfAnyUnquoted "abcdef test" "t" '"' '"' 5 6)
if [[ "$result" == "7" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - start and count"
else
    kk_test_fail "IndexOfAnyUnquoted - start and count (expected: 8 or -1, got: '$result')"
fi

# Test 12: Empty string
kk_test_start "IndexOfAnyUnquoted - empty string"
result=$(string.indexOfAnyUnquoted "" "a" '"' '"')
if [[ "$result" == "-1" ]]; then
    kk_test_pass "IndexOfAnyUnquoted - empty string"
else
    kk_test_fail "IndexOfAnyUnquoted - empty string (expected: -1, got: '$result')"
fi
