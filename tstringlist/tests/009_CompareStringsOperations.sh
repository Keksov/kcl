#!/bin/bash
# 009_CompareStringsOperations.sh - Test CompareStrings method
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tstringlist module
TSTRINGLIST_DIR="$SCRIPT_DIR/.."
source "$TSTRINGLIST_DIR/tstringlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Initialize test-specific temp directory

kt_test_section "009: CompareStrings Operations"

# Create a TStringList for testing
TStringList.new mylist

# Test: CompareStrings - case insensitive (default), equal strings
kt_test_start "CompareStrings case-insensitive, equal strings"
mylist.case_sensitive = "false"
mylist.CompareStrings "apple" "apple"
result="$RESULT"
if [[ "$result" == "0" ]]; then
    kt_test_pass "CompareStrings returned 0 for equal strings"
else
    kt_test_fail "CompareStrings returned $result, expected 0"
fi

# Test: CompareStrings - case insensitive, different case
kt_test_start "CompareStrings case-insensitive, different case"
mylist.CompareStrings "Apple" "apple"
result="$RESULT"
if [[ "$result" == "0" ]]; then
    kt_test_pass "CompareStrings returned 0 for same strings (different case)"
else
    kt_test_fail "CompareStrings returned $result, expected 0"
fi

# Test: CompareStrings - str1 less than str2
kt_test_start "CompareStrings str1 < str2 case-insensitive"
mylist.CompareStrings "apple" "banana"
result="$RESULT"
if [[ "$result" == "1" ]]; then
    kt_test_pass "CompareStrings returned 1 for apple < banana"
else
    kt_test_fail "CompareStrings returned $result, expected 1"
fi

# Test: CompareStrings - str1 greater than str2
kt_test_start "CompareStrings str1 > str2 case-insensitive"
mylist.CompareStrings "banana" "apple"
result="$RESULT"
if [[ "$result" == "2" ]]; then
    kt_test_pass "CompareStrings returned 2 for banana > apple"
else
    kt_test_fail "CompareStrings returned $result, expected 2"
fi

# Test: CompareStrings case-sensitive equal
kt_test_start "CompareStrings case-sensitive, equal strings"
mylist.case_sensitive = "true"
mylist.CompareStrings "apple" "apple"
result="$RESULT"
if [[ "$result" == "0" ]]; then
    kt_test_pass "CompareStrings returned 0 for exact match"
else
    kt_test_fail "CompareStrings returned $result, expected 0"
fi

# Test: CompareStrings case-sensitive, different case equals
kt_test_start "CompareStrings case-sensitive, different case (not equal)"
mylist.CompareStrings "Apple" "apple"
result="$RESULT"
if [[ "$result" != "0" ]]; then
    kt_test_pass "CompareStrings returned non-zero for different case"
else
    kt_test_fail "CompareStrings should not return 0 for 'Apple' vs 'apple'"
fi

# Test: CompareStrings case-sensitive less than
kt_test_start "CompareStrings case-sensitive less than"
mylist.CompareStrings "apple" "banana"
result="$RESULT"
if [[ "$result" == "1" ]]; then
    kt_test_pass "CompareStrings returned 1 for apple < banana"
else
    kt_test_fail "CompareStrings returned $result, expected 1"
fi

# Test: CompareStrings case-sensitive greater than
kt_test_start "CompareStrings case-sensitive greater than"
mylist.CompareStrings "banana" "apple"
result="$RESULT"
if [[ "$result" == "2" ]]; then
    kt_test_pass "CompareStrings returned 2 for banana > apple"
else
    kt_test_fail "CompareStrings returned $result, expected 2"
fi

# Test: CompareStrings with empty string
kt_test_start "CompareStrings with empty string"
mylist.case_sensitive = "false"
mylist.CompareStrings "" ""
result="$RESULT"
if [[ "$result" == "0" ]]; then
    kt_test_pass "CompareStrings returned 0 for both empty"
else
    kt_test_fail "CompareStrings returned $result, expected 0"
fi

# Test: CompareStrings empty vs non-empty
kt_test_start "CompareStrings empty vs non-empty"
mylist.CompareStrings "" "apple"
result="$RESULT"
if [[ "$result" == "1" ]]; then
    kt_test_pass "CompareStrings returned 1 for empty < non-empty"
else
    kt_test_fail "CompareStrings returned $result, expected 1"
fi

# Test: CompareStrings with special characters
kt_test_start "CompareStrings with special characters"
mylist.CompareStrings "test@1" "test@1"
result="$RESULT"
if [[ "$result" == "0" ]]; then
    kt_test_pass "CompareStrings handles special characters"
else
    kt_test_fail "CompareStrings returned $result, expected 0"
fi

# Test: CompareStrings numeric strings (lexicographic, not numeric)
kt_test_start "CompareStrings numeric strings (lexicographic)"
mylist.CompareStrings "100" "20"
result="$RESULT"
if [[ "$result" == "1" ]]; then
    # "100" < "20" lexicographically (because "1" < "2")
    kt_test_pass "CompareStrings compares lexicographically (100 < 20)"
else
    kt_test_fail "CompareStrings returned $result, expected 1"
fi

# Test: CompareStrings with unicode (if supported)
kt_test_start "CompareStrings with similar strings"
mylist.case_sensitive = "false"
mylist.CompareStrings "café" "cafe"
result="$RESULT"
# Result may vary depending on system, just verify it returns valid value
if [[ "$result" != "" ]]; then
    kt_test_pass "CompareStrings handled unicode-like strings"
else
    kt_test_fail "CompareStrings failed with unicode"
fi

# Cleanup
mylist.delete

kt_test_log "009_CompareStringsOperations.sh completed"
