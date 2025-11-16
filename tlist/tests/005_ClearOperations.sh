#!/bin/bash
# 005_clear_operations.sh - Test Clear method

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "005"

test_section "005: Clear Operations"

# Create TList instance and add items
TList.new mylist
for i in {1..10}; do
    mylist.Add "item$i"
done

initial_count=$(mylist.count)
initial_capacity=$(mylist.capacity)

# Test: Clear the list
test_start "Clear list"
mylist.Clear
count=$(mylist.count)
capacity=$(mylist.capacity)

if [[ "$count" == "0" && "$capacity" == "0" ]]; then
    test_pass "List cleared successfully (Count=0, Capacity=0)"
else
    test_fail "After Clear: Count=$count (expected 0), Capacity=$capacity (expected 0)"
fi

# Test: Add items after clear
test_start "Add items after clear"
mylist.Add "new_item1"
mylist.Add "new_item2"
count=$(mylist.count)
if [[ "$count" == "2" ]]; then
    mylist.First && first=$RESULT
    mylist.Last && last=$RESULT
    if [[ "$first" == "new_item1" && "$last" == "new_item2" ]]; then
        test_pass "Can add items after clear"
    else
        test_fail "Items after clear: First='$first', Last='$last'"
    fi
else
    test_fail "Count after adding 2 items: $count (expected 2)"
fi

# Test: Clear empty list
test_start "Clear empty list"
mylist.Clear
count=$(mylist.count)
capacity=$(mylist.capacity)
if [[ "$count" == "0" && "$capacity" == "0" ]]; then
    test_pass "Clear empty list works"
else
    test_fail "Clear empty list: Count=$count, Capacity=$capacity"
fi

# Test: Clear with large capacity
test_start "Clear list with large capacity"
for i in {1..100}; do
    mylist.Add "item$i"
done
large_capacity=$(mylist.capacity)
mylist.Clear
count=$(mylist.count)
capacity=$(mylist.capacity)
if [[ "$count" == "0" && "$capacity" == "0" ]]; then
    test_pass "Clear large list resets capacity to 0"
else
    test_fail "Clear large list: Count=$count, Capacity=$capacity"
fi

# Cleanup
mylist.delete

test_info "005_clear_operations.sh completed"
