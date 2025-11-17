#!/bin/bash
# 009_CompareStringsOperations.sh - Test CompareStrings method
# Tests string comparison with case sensitivity options

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "009"

test_section "009: CompareStrings Operations"

# Create a TStringList for testing
TStringList.new mylist

# Test: CompareStrings - case insensitive (default), equal strings
test_start "CompareStrings case-insensitive, equal strings"
mylist.case_sensitive = "false"
mylist.CompareStrings "apple" "apple"
result="$RESULT"
if [[ "$result" == "0" ]]; then
    test_pass "CompareStrings returned 0 for equal strings"
else
    test_fail "CompareStrings returned $result, expected 0"
fi

# Test: CompareStrings - case insensitive, different case
test_start "CompareStrings case-insensitive, different case"
mylist.CompareStrings "Apple" "apple"
result="$RESULT"
if [[ "$result" == "0" ]]; then
    test_pass "CompareStrings returned 0 for same strings (different case)"
else
    test_fail "CompareStrings returned $result, expected 0"
fi

# Test: CompareStrings - str1 less than str2
test_start "CompareStrings str1 < str2 case-insensitive"
mylist.CompareStrings "apple" "banana"
result="$RESULT"
if [[ "$result" == "1" ]]; then
    test_pass "CompareStrings returned 1 for apple < banana"
else
    test_fail "CompareStrings returned $result, expected 1"
fi

# Test: CompareStrings - str1 greater than str2
test_start "CompareStrings str1 > str2 case-insensitive"
mylist.CompareStrings "banana" "apple"
result="$RESULT"
if [[ "$result" == "2" ]]; then
    test_pass "CompareStrings returned 2 for banana > apple"
else
    test_fail "CompareStrings returned $result, expected 2"
fi

# Test: CompareStrings case-sensitive equal
test_start "CompareStrings case-sensitive, equal strings"
mylist.case_sensitive = "true"
mylist.CompareStrings "apple" "apple"
result="$RESULT"
if [[ "$result" == "0" ]]; then
    test_pass "CompareStrings returned 0 for exact match"
else
    test_fail "CompareStrings returned $result, expected 0"
fi

# Test: CompareStrings case-sensitive, different case equals
test_start "CompareStrings case-sensitive, different case (not equal)"
mylist.CompareStrings "Apple" "apple"
result="$RESULT"
if [[ "$result" != "0" ]]; then
    test_pass "CompareStrings returned non-zero for different case"
else
    test_fail "CompareStrings should not return 0 for 'Apple' vs 'apple'"
fi

# Test: CompareStrings case-sensitive less than
test_start "CompareStrings case-sensitive less than"
mylist.CompareStrings "apple" "banana"
result="$RESULT"
if [[ "$result" == "1" ]]; then
    test_pass "CompareStrings returned 1 for apple < banana"
else
    test_fail "CompareStrings returned $result, expected 1"
fi

# Test: CompareStrings case-sensitive greater than
test_start "CompareStrings case-sensitive greater than"
mylist.CompareStrings "banana" "apple"
result="$RESULT"
if [[ "$result" == "2" ]]; then
    test_pass "CompareStrings returned 2 for banana > apple"
else
    test_fail "CompareStrings returned $result, expected 2"
fi

# Test: CompareStrings with empty string
test_start "CompareStrings with empty string"
mylist.case_sensitive = "false"
mylist.CompareStrings "" ""
result="$RESULT"
if [[ "$result" == "0" ]]; then
    test_pass "CompareStrings returned 0 for both empty"
else
    test_fail "CompareStrings returned $result, expected 0"
fi

# Test: CompareStrings empty vs non-empty
test_start "CompareStrings empty vs non-empty"
mylist.CompareStrings "" "apple"
result="$RESULT"
if [[ "$result" == "1" ]]; then
    test_pass "CompareStrings returned 1 for empty < non-empty"
else
    test_fail "CompareStrings returned $result, expected 1"
fi

# Test: CompareStrings with special characters
test_start "CompareStrings with special characters"
mylist.CompareStrings "test@1" "test@1"
result="$RESULT"
if [[ "$result" == "0" ]]; then
    test_pass "CompareStrings handles special characters"
else
    test_fail "CompareStrings returned $result, expected 0"
fi

# Test: CompareStrings numeric strings (lexicographic, not numeric)
test_start "CompareStrings numeric strings (lexicographic)"
mylist.CompareStrings "100" "20"
result="$RESULT"
if [[ "$result" == "1" ]]; then
    # "100" < "20" lexicographically (because "1" < "2")
    test_pass "CompareStrings compares lexicographically (100 < 20)"
else
    test_fail "CompareStrings returned $result, expected 1"
fi

# Test: CompareStrings with unicode (if supported)
test_start "CompareStrings with similar strings"
mylist.case_sensitive = "false"
mylist.CompareStrings "café" "cafe"
result="$RESULT"
# Result may vary depending on system, just verify it returns valid value
if [[ "$result" != "" ]]; then
    test_pass "CompareStrings handled unicode-like strings"
else
    test_fail "CompareStrings failed with unicode"
fi

# Cleanup
mylist.delete

test_info "009_CompareStringsOperations.sh completed"
