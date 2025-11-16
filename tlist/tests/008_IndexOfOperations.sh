#!/bin/bash
# 008_indexof_operations.sh - Test IndexOf method

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "008"

test_section "008: IndexOf Operations"

# Create TList instance and add items
TList.new mylist
mylist.Add "apple"
mylist.Add "banana"
mylist.Add "cherry"
mylist.Add "banana"
mylist.Add "date"

# Test: IndexOf existing item (first occurrence)
test_start "IndexOf first occurrence"
mylist.IndexOf "banana"
index=$RESULT
if [[ "$index" == "1" ]]; then
    test_pass "IndexOf 'banana' returned 1 (first occurrence)"
else
    test_fail "IndexOf 'banana' returned $index, expected 1"
fi

# Test: IndexOf first item
test_start "IndexOf first item"
mylist.IndexOf "apple"
index=$RESULT
if [[ "$index" == "0" ]]; then
    test_pass "IndexOf 'apple' returned 0"
else
    test_fail "IndexOf 'apple' returned $index, expected 0"
fi

# Test: IndexOf last item
test_start "IndexOf last item"
mylist.IndexOf "date"
index=$RESULT
if [[ "$index" == "4" ]]; then
    test_pass "IndexOf 'date' returned 4"
else
    test_fail "IndexOf 'date' returned $index, expected 4"
fi

# Test: IndexOf non-existing item
test_start "IndexOf non-existing item"
mylist.IndexOf "grape"
index=$RESULT
if [[ "$index" == "-1" ]]; then
    test_pass "IndexOf 'grape' returned -1 (not found)"
else
    test_fail "IndexOf 'grape' returned $index, expected -1"
fi

# Test: IndexOf empty string
test_start "IndexOf empty string"
mylist.Add ""
mylist.IndexOf ""
index=$RESULT
if [[ "$index" == "5" ]]; then
    test_pass "IndexOf empty string returned 5"
else
    test_fail "IndexOf empty string returned $index, expected 5"
fi

# Test: IndexOf on empty list
test_start "IndexOf on empty list"
TList.new emptylist
emptylist.IndexOf "anything"
index=$RESULT
if [[ "$index" == "-1" ]]; then
    test_pass "IndexOf on empty list returned -1"
else
    test_fail "IndexOf on empty list returned $index, expected -1"
fi
emptylist.delete

# Test: IndexOf null/empty pointer (if supported)
test_start "IndexOf null value"
# Add an empty item
mylist.Add ""
mylist.Add ""
mylist.IndexOf ""
index=$RESULT
if [[ "$index" == "5" ]]; then
    test_pass "IndexOf empty string works with multiple empty items"
else
    test_fail "IndexOf empty string returned $index, expected 5"
fi

# Cleanup
mylist.delete

test_info "008_indexof_operations.sh completed"
