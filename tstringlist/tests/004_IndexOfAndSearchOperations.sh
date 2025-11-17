#!/bin/bash
# 004_IndexOfAndSearchOperations.sh - Test IndexOf and search operations
# Tests finding strings in the list with case sensitivity options

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "004"

test_section "004: IndexOf and Search Operations"

# Create TStringList with some test data
TStringList.new mylist
mylist.Add "apple"
mylist.Add "Banana"
mylist.Add "CHERRY"
mylist.Add "date"
mylist.Add "apple"  # Duplicate for testing

# Test: IndexOf with exact match
test_start "IndexOf with exact match"
mylist.IndexOf "apple"
index=$RESULT
if [[ "$index" == "0" ]]; then
    test_pass "IndexOf found 'apple' at index 0"
else
    test_fail "IndexOf returned $index, expected 0"
fi

# Test: IndexOf with case-insensitive search (default)
test_start "IndexOf case-insensitive search (default)"
mylist.IndexOf "banana"
index=$RESULT
if [[ "$index" == "1" ]]; then
    test_pass "IndexOf found 'banana' case-insensitively at index 1"
else
    test_fail "IndexOf returned $index, expected 1"
fi

# Test: IndexOf with non-existent string
test_start "IndexOf with non-existent string"
mylist.IndexOf "grape"
index=$RESULT
if [[ "$index" == "-1" ]]; then
    test_pass "IndexOf returned -1 for non-existent string"
else
    test_fail "IndexOf returned $index, expected -1"
fi

# Test: IndexOf returns first occurrence
test_start "IndexOf returns first occurrence of duplicates"
mylist.IndexOf "apple"
index=$RESULT
if [[ "$index" == "0" ]]; then
    test_pass "IndexOf returned first occurrence at index 0"
else
    test_fail "IndexOf returned $index, expected 0 (first occurrence)"
fi

# Test: IndexOf with CHERRY in uppercase
test_start "IndexOf with uppercase string"
mylist.IndexOf "cherry"
index=$RESULT
if [[ "$index" == "2" ]]; then
    test_pass "IndexOf found 'cherry' case-insensitively at index 2"
else
    test_fail "IndexOf returned $index, expected 2"
fi

# Test: IndexOf with date
test_start "IndexOf with another string"
mylist.IndexOf "date"
index=$RESULT
if [[ "$index" == "3" ]]; then
    test_pass "IndexOf found 'date' at index 3"
else
    test_fail "IndexOf returned $index, expected 3"
fi

# Test: Case-sensitive property (change to true)
test_start "Test case-sensitive property"
mylist.case_sensitive = "true"
mylist.IndexOf "Banana"
index=$RESULT
if [[ "$index" == "1" ]]; then
    test_pass "Case-sensitive search found 'Banana' at index 1"
else
    test_fail "Case-sensitive IndexOf returned $index, expected 1"
fi

# Test: Case-sensitive search should fail for different case
test_start "Case-sensitive search fails for different case"
mylist.case_sensitive = "true"
mylist.IndexOf "banana"
index=$RESULT
if [[ "$index" == "-1" ]]; then
    test_pass "Case-sensitive IndexOf returned -1 for 'banana' (list has 'Banana')"
else
    test_fail "Case-sensitive IndexOf returned $index, expected -1"
fi

# Reset to case-insensitive
mylist.case_sensitive = "false"

# Test: IndexOf with empty list
test_start "IndexOf with empty string in list"
TStringList.new emptytest
emptytest.Add ""
emptytest.Add "nonempty"
emptytest.IndexOf ""
index=$RESULT
if [[ "$index" == "0" ]]; then
    test_pass "IndexOf found empty string at index 0"
else
    test_fail "IndexOf returned $index, expected 0"
fi
emptytest.delete

# Test: IndexOf in large list
test_start "IndexOf in large list"
TStringList.new largelist
for i in {1..100}; do
    largelist.Add "item$i"
done
largelist.IndexOf "item50"
index=$RESULT
if [[ "$index" == "49" ]]; then
    test_pass "IndexOf found 'item50' at index 49 in large list"
else
    test_fail "IndexOf returned $index, expected 49"
fi
largelist.delete

# Cleanup
mylist.delete

test_info "004_IndexOfAndSearchOperations.sh completed"
