#!/bin/bash
# 002_add_and_basic_operations.sh - Test Add method and basic operations

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "002"

test_section "002: Add Method and Basic Operations"

# Create TList instance
TList.new mylist

# Test: Add single item
test_start "Add single item"
mylist.Add "item1"
count=$(mylist.count)
if [[ "$count" == "1" ]]; then
    test_pass "Added item and count is 1"
else
    test_fail "Count is $count, expected 1"
fi

# Test: Add multiple items
test_start "Add multiple items"
mylist.Add "item2"
count=${TLIST_ADD}
if [[ "$count" == "2" ]]; then
    test_pass "Count is 2 after adding two items"
else
    test_fail "Count is $count, expected 2"
fi

mylist.Add "item3" 
count=$RESULT
if [[ "$count" == "3" ]]; then
    test_pass "Count is 3 after adding three items"
else
    test_fail "Count is $count, expected 3"
fi

# Test: Capacity growth
test_start "Capacity growth on Add"
capacity=$(mylist.capacity)
if [[ "$capacity" -ge "$count" ]]; then
    test_pass "Capacity ($capacity) >= Count ($count)"
else
    test_fail "Capacity ($capacity) < Count ($count)"
fi

# Test: Add many items to force capacity growth
test_start "Add many items to test capacity growth"
initial_capacity=$capacity
for i in {4..20}; do
    mylist.Add "item$i" >/dev/null
done
final_count=$(mylist.count)
final_capacity=$(mylist.capacity)
if [[ "$final_count" == "20" && "$final_capacity" -ge "$final_count" ]]; then
    test_pass "Added 20 items, capacity grew appropriately"
else
    test_fail "Count: $final_count (expected 20), Capacity: $final_capacity"
fi

# Test: First and Last
test_start "First and Last methods"
mylist.First && first=$RESULT
mylist.Last && last=$TLIST_LAST
if [[ "$first" == "item1" && "$last" == "item20" ]]; then
    test_pass "First and Last return correct items"
else
    test_fail "First: '$first' (expected 'item1'), Last: '$last' (expected 'item20')"
fi

# Cleanup
mylist.delete

test_info "002_add_and_basic_operations.sh completed"
