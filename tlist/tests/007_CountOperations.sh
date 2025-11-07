#!/bin/bash
# 007_count_operations.sh - Test Count and SetCount methods

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Initialize test-specific temp directory
init_test_tmpdir "007"

test_section "007: Count Operations"

# Create TList instance
TList.new mylist

# Test: Initial count
test_start "Initial count"
count=$(mylist.Count)
if [[ "$count" == "0" ]]; then
    test_pass "Initial count is 0"
else
    test_fail "Initial count is $count, expected 0"
fi

# Test: Add items and check count
test_start "Count after adding items"
for i in {1..5}; do
    mylist.Add "item$i"
done
count=$(mylist.Count)
if [[ "$count" == "5" ]]; then
    test_pass "Count is 5 after adding 5 items"
else
    test_fail "Count is $count, expected 5"
fi

# Test: SetCount to increase (add nil items)
test_start "SetCount to increase"
mylist.SetCount 10
count=$(mylist.Count)
capacity=$(mylist.Capacity)
if [[ "$count" == "10" && "$capacity" -ge "10" ]]; then
    test_pass "SetCount increased to 10"
else
    test_fail "Count=$count (expected 10), Capacity=$capacity (expected >=10)"
fi

# Test: Check that new items are empty/nil
test_start "New items from SetCount are empty"
items_var="mylist_items"
declare -n items_ref="$items_var"
if [[ "${items_ref[5]}" == "" && "${items_ref[9]}" == "" ]]; then
    test_pass "New items from SetCount are empty"
else
    test_fail "New items not empty: index 5='${items_ref[5]}', index 9='${items_ref[9]}'"
fi

# Test: SetCount to decrease (truncate)
test_start "SetCount to decrease"
mylist.SetCount 3
count=$(mylist.Count)
if [[ "$count" == "3" ]]; then
    test_pass "SetCount decreased to 3"
else
    test_fail "Count is $count, expected 3"
fi

# Test: SetCount to 0
test_start "SetCount to 0"
mylist.SetCount 0
count=$(mylist.Count)
if [[ "$count" == "0" ]]; then
    test_pass "SetCount to 0 clears list"
else
    test_fail "Count is $count, expected 0"
fi

# Test: SetCount on empty list
test_start "SetCount on empty list"
mylist.SetCount 5
count=$(mylist.Count)
capacity=$(mylist.Capacity)
if [[ "$count" == "5" && "$capacity" -ge "5" ]]; then
    test_pass "SetCount to 5 on empty list"
else
    test_fail "Count=$count (expected 5), Capacity=$capacity (expected >=5)"
fi

# Cleanup
mylist.delete

test_info "007_count_operations.sh completed"
