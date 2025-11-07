#!/bin/bash
# 009_remove_operations.sh - Test Remove method

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

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
removed_index=$(mylist.Remove "banana")
count=$(mylist.Count)
if [[ "$removed_index" == "1" && "$count" == "4" ]]; then
    # Should now be: apple, cherry, banana, date
    items_var="mylist_items"
    declare -n items_ref="$items_var"
    if [[ "${items_ref[1]}" == "cherry" && "${items_ref[2]}" == "banana" ]]; then
        test_pass "Removed first 'banana' at index 1"
    else
        test_fail "Items after remove: [1]='${items_ref[1]}', [2]='${items_ref[2]}'"
    fi
else
    test_fail "Removed index: $removed_index (expected 1), Count: $count (expected 4)"
fi

# Test: Remove another occurrence
test_start "Remove second occurrence"
removed_index=$(mylist.Remove "banana")
count=$(mylist.Count)
if [[ "$removed_index" == "2" && "$count" == "3" ]]; then
    # Should now be: apple, cherry, date
    declare -n items_ref="$items_var"
    if [[ "${items_ref[0]}" == "apple" && "${items_ref[1]}" == "cherry" && "${items_ref[2]}" == "date" ]]; then
        test_pass "Removed second 'banana' at index 2"
    else
        test_fail "Final items: [0]='${items_ref[0]}', [1]='${items_ref[1]}', [2]='${items_ref[2]}'"
    fi
else
    test_fail "Removed index: $removed_index (expected 2), Count: $count (expected 3)"
fi

# Test: Remove non-existing item
test_start "Remove non-existing item"
removed_index=$(mylist.Remove "grape")
count=$(mylist.Count)
if [[ "$removed_index" == "-1" && "$count" == "3" ]]; then
    test_pass "Remove non-existing item returned -1"
else
    test_fail "Removed index: $removed_index (expected -1), Count: $count (expected 3)"
fi

# Test: Remove from list with one item
test_start "Remove from single-item list"
TList.new singlelist
singlelist.Add "single"
removed_index=$(singlelist.Remove "single")
count=$(singlelist.Count)
if [[ "$removed_index" == "0" && "$count" == "0" ]]; then
    test_pass "Removed from single-item list"
else
    test_fail "Removed index: $removed_index (expected 0), Count: $count (expected 0)"
fi
singlelist.delete

# Test: Remove empty string
test_start "Remove empty string"
mylist.Add ""
removed_index=$(mylist.Remove "")
count=$(mylist.Count)
if [[ "$removed_index" == "3" && "$count" == "3" ]]; then
    test_pass "Removed empty string"
else
    test_fail "Removed index: $removed_index (expected 3), Count: $count (expected 3)"
fi

# Cleanup
mylist.delete

test_info "009_remove_operations.sh completed"
