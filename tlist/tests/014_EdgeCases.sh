#!/bin/bash
# 014_edge_cases.sh - Test edge cases and error conditions

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Initialize test-specific temp directory
init_test_tmpdir "014"

test_section "014: Edge Cases and Error Conditions"

# Test: Operations on destroyed instance
test_start "Operations on destroyed instance"
TList.new temp_list
temp_list.delete

# Try to call methods on destroyed instance
temp_list.Count 2>/dev/null
result=$?
if [[ $result -ne 0 ]]; then
    test_pass "Operations on destroyed instance fail gracefully"
else
    test_fail "Operations on destroyed instance should fail"
fi

# Test: Very large capacity
test_start "Very large capacity"
TList.new biglist
biglist.SetCapacity 10000
capacity=$(biglist.Capacity)
if [[ "$capacity" == "10000" ]]; then
    test_pass "SetCapacity to 10000 works"
else
    test_fail "Capacity is $capacity, expected 10000"
fi
biglist.delete

# Test: Add empty strings
test_start "Add empty strings"
TList.new emptylist
emptylist.Add ""
emptylist.Add ""
emptylist.Add ""
count=$(emptylist.Count)
if [[ "$count" == "3" ]]; then
    test_pass "Added empty strings successfully"
else
    test_fail "Count after adding empty strings: $count (expected 3)"
fi
emptylist.delete

# Test: Insert at position 0 in empty list (should fail or handle)
test_start "Insert at 0 in empty list"
TList.new insertlist
insertlist.Insert 0 "test" 2>/dev/null
result=$?
count=$(insertlist.Count)
if [[ $result -ne 0 || "$count" == "0" ]]; then
    test_pass "Insert at 0 in empty list handled appropriately"
else
    test_fail "Insert at 0 in empty list succeeded unexpectedly"
fi
insertlist.delete

# Test: Delete from empty list
test_start "Delete from empty list"
TList.new dellist
dellist.Delete 0 2>/dev/null
result=$?
if [[ $result -ne 0 ]]; then
    test_pass "Delete from empty list fails gracefully"
else
    test_fail "Delete from empty list should fail"
fi
dellist.delete

# Test: IndexOf in list with duplicate items
test_start "IndexOf with duplicates"
TList.new duplist
duplist.Add "dup"
duplist.Add "unique"
duplist.Add "dup"
duplist.Add "dup"
index1=$(duplist.IndexOf "dup")
index2=$(duplist.IndexOf "unique")
if [[ "$index1" == "0" && "$index2" == "1" ]]; then
    test_pass "IndexOf finds first occurrence"
else
    test_fail "IndexOf results: dup=$index1 (expected 0), unique=$index2 (expected 1)"
fi
duplist.delete

# Test: Remove all occurrences of an item
test_start "Remove all occurrences"
TList.new remlist
remlist.Add "keep"
remlist.Add "remove"
remlist.Add "keep"
remlist.Add "remove"
remlist.Remove "remove"
remlist.Remove "remove"
count=$(remlist.Count)
if [[ "$count" == "2" ]]; then
    items_var="remlist_items"
    declare -n items_ref="$items_var"
    if [[ "${items_ref[0]}" == "keep" && "${items_ref[1]}" == "keep" ]]; then
        test_pass "Removed all occurrences of item"
    else
        test_fail "Items after remove: [0]='${items_ref[0]}', [1]='${items_ref[1]}'"
    fi
else
    test_fail "Count after removing all 'remove': $count (expected 2)"
fi
remlist.delete

# Test: Capacity vs Count relationship
test_start "Capacity always >= Count"
TList.new caplist
caplist.Add "test"
caplist.SetCapacity 10
count=$(caplist.Count)
capacity=$(caplist.Capacity)
if [[ "$capacity" -ge "$count" ]]; then
    test_pass "Capacity >= Count maintained"
else
    test_fail "Capacity $capacity < Count $count"
fi
caplist.delete

test_info "014_edge_cases.sh completed"
