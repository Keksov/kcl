#!/bin/bash
# 004_IndexOfAndSearchOperations.sh - Test IndexOf and search operations
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

kt_test_section "004: IndexOf and Search Operations"

# Create TStringList with some test data
TStringList.new mylist
mylist.Add "apple"
mylist.Add "Banana"
mylist.Add "CHERRY"
mylist.Add "date"
mylist.Add "apple"  # Duplicate for testing

# Test: IndexOf with exact match
kt_test_start "IndexOf with exact match"
mylist.IndexOf "apple"
index=$RESULT
if [[ "$index" == "0" ]]; then
    kt_test_pass "IndexOf found 'apple' at index 0"
else
    kt_test_fail "IndexOf returned $index, expected 0"
fi

# Test: IndexOf with case-insensitive search (default)
kt_test_start "IndexOf case-insensitive search (default)"
mylist.IndexOf "banana"
index=$RESULT
if [[ "$index" == "1" ]]; then
    kt_test_pass "IndexOf found 'banana' case-insensitively at index 1"
else
    kt_test_fail "IndexOf returned $index, expected 1"
fi

# Test: IndexOf with non-existent string
kt_test_start "IndexOf with non-existent string"
mylist.IndexOf "grape"
index=$RESULT
if [[ "$index" == "-1" ]]; then
    kt_test_pass "IndexOf returned -1 for non-existent string"
else
    kt_test_fail "IndexOf returned $index, expected -1"
fi

# Test: IndexOf returns first occurrence
kt_test_start "IndexOf returns first occurrence of duplicates"
mylist.IndexOf "apple"
index=$RESULT
if [[ "$index" == "0" ]]; then
    kt_test_pass "IndexOf returned first occurrence at index 0"
else
    kt_test_fail "IndexOf returned $index, expected 0 (first occurrence)"
fi

# Test: IndexOf with CHERRY in uppercase
kt_test_start "IndexOf with uppercase string"
mylist.IndexOf "cherry"
index=$RESULT
if [[ "$index" == "2" ]]; then
    kt_test_pass "IndexOf found 'cherry' case-insensitively at index 2"
else
    kt_test_fail "IndexOf returned $index, expected 2"
fi

# Test: IndexOf with date
kt_test_start "IndexOf with another string"
mylist.IndexOf "date"
index=$RESULT
if [[ "$index" == "3" ]]; then
    kt_test_pass "IndexOf found 'date' at index 3"
else
    kt_test_fail "IndexOf returned $index, expected 3"
fi

# Test: Case-sensitive property (change to true)
kt_test_start "Test case-sensitive property"
mylist.case_sensitive = "true"
mylist.IndexOf "Banana"
index=$RESULT
if [[ "$index" == "1" ]]; then
    kt_test_pass "Case-sensitive search found 'Banana' at index 1"
else
    kt_test_fail "Case-sensitive IndexOf returned $index, expected 1"
fi

# Test: Case-sensitive search should fail for different case
kt_test_start "Case-sensitive search fails for different case"
mylist.case_sensitive = "true"
mylist.IndexOf "banana"
index=$RESULT
if [[ "$index" == "-1" ]]; then
    kt_test_pass "Case-sensitive IndexOf returned -1 for 'banana' (list has 'Banana')"
else
    kt_test_fail "Case-sensitive IndexOf returned $index, expected -1"
fi

# Reset to case-insensitive
mylist.case_sensitive = "false"

# Test: IndexOf with empty list
kt_test_start "IndexOf with empty string in list"
TStringList.new emptytest
emptytest.Add ""
emptytest.Add "nonempty"
emptytest.IndexOf ""
index=$RESULT
if [[ "$index" == "0" ]]; then
    kt_test_pass "IndexOf found empty string at index 0"
else
    kt_test_fail "IndexOf returned $index, expected 0"
fi
emptytest.delete

# Test: IndexOf in large list
kt_test_start "IndexOf in large list"
TStringList.new largelist
for i in {1..100}; do
    largelist.Add "item$i"
done
largelist.IndexOf "item50"
index=$RESULT
if [[ "$index" == "49" ]]; then
    kt_test_pass "IndexOf found 'item50' at index 49 in large list"
else
    kt_test_fail "IndexOf returned $index, expected 49"
fi
largelist.delete

# Cleanup
mylist.delete

kt_test_log "004_IndexOfAndSearchOperations.sh completed"
