#!/bin/bash
# 009_remove_operations.sh - Test Remove method

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "009"

test_section "009: Remove Operations"

# Create TList instance and add items
TList.new mylist
mylist.Add "apple"
mylist.Add "banana"
mylist.Add "cherry"
mylist.Add "banana"
mylist.Add "date"

# Test: Remove existing item (first occurrence)
test_start "Remove first occurrence"
mylist.Remove "banana"
removed_index=$RESULT
count=$(mylist.count)
# After removing banana at index 1: apple, cherry, banana, date
if [[ "$count" == "4" && "$removed_index" == "1" ]]; then
    test_pass "Removed first 'banana' at index 1"
else
    test_fail "Count: $count (expected 4), Removed index: $removed_index (expected 1)"
fi

# Test: Remove another occurrence
test_start "Remove second occurrence"
mylist.Remove "banana"
removed_index=$RESULT
count=$(mylist.count)
# Should now be: apple, cherry, date
if [[ "$count" == "3" && "$removed_index" == "2" ]]; then
    test_pass "Removed second 'banana' at index 2"
else
    test_fail "Count: $count (expected 3), Removed index: $removed_index (expected 2)"
fi

# Test: Remove non-existing item
test_start "Remove non-existing item"
mylist.Remove "grape"
removed_index=$RESULT
count=$(mylist.count)
if [[ "$count" == "3" && "$removed_index" == "-1" ]]; then
    test_pass "Remove non-existing item didn't change count"
else
    test_fail "Count: $count (expected 3), Removed index: $removed_index (expected -1)"
fi

# Test: Remove from list with one item
test_start "Remove from single-item list"
TList.new singlelist
singlelist.Add "single"
singlelist.Remove "single"
count=$(singlelist.count)
if [[ "$count" == "0" ]]; then
    test_pass "Removed from single-item list"
else
    test_fail "Count: $count (expected 0)"
fi
singlelist.delete

# Test: Remove empty string
test_start "Remove empty string"
mylist.Add ""
mylist.Remove ""
count=$(mylist.count)
if [[ "$count" == "3" ]]; then
    test_pass "Removed empty string"
else
    test_fail "Count: $count (expected 3)"
fi

# Cleanup
mylist.delete

test_info "009_remove_operations.sh completed"
