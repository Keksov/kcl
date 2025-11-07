#!/bin/bash
# 006_capacity_operations.sh - Test Capacity and SetCapacity methods

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Initialize test-specific temp directory
init_test_tmpdir "006"

test_section "006: Capacity Operations"

# Create TList instance
TList.new mylist

# Test: Initial capacity
test_start "Initial capacity"
capacity=$(mylist.Capacity)
if [[ "$capacity" == "0" ]]; then
    test_pass "Initial capacity is 0"
else
    test_fail "Initial capacity is $capacity, expected 0"
fi

# Test: SetCapacity on empty list
test_start "SetCapacity on empty list"
mylist.SetCapacity 10
capacity=$(mylist.Capacity)
count=$(mylist.Count)
if [[ "$capacity" == "10" && "$count" == "0" ]]; then
    test_pass "SetCapacity to 10 on empty list"
else
    test_fail "Capacity=$capacity (expected 10), Count=$count (expected 0)"
fi

# Test: Add items up to capacity
test_start "Add items up to capacity"
for i in {1..10}; do
    mylist.Add "item$i"
done
count=$(mylist.Count)
capacity=$(mylist.Capacity)
if [[ "$count" == "10" && "$capacity" == "10" ]]; then
    test_pass "Added items up to capacity"
else
    test_fail "Count=$count (expected 10), Capacity=$capacity (expected 10)"
fi

# Test: Add beyond capacity (should grow)
test_start "Add beyond capacity"
mylist.Add "item11"
count=$(mylist.Count)
capacity=$(mylist.Capacity)
if [[ "$count" == "11" && "$capacity" -ge "11" ]]; then
    test_pass "Capacity grew when adding beyond limit"
else
    test_fail "Count=$count (expected 11), Capacity=$capacity (expected >=11)"
fi

# Test: Reduce capacity below count (should truncate)
test_start "Reduce capacity below count"
mylist.SetCapacity 5
count=$(mylist.Count)
capacity=$(mylist.Capacity)
if [[ "$count" == "5" && "$capacity" == "5" ]]; then
    test_pass "Capacity reduction truncated list"
else
    test_fail "Count=$count (expected 5), Capacity=$capacity (expected 5)"
fi

# Test: Set capacity to 0
test_start "Set capacity to 0"
mylist.SetCapacity 0
count=$(mylist.Count)
capacity=$(mylist.Capacity)
if [[ "$count" == "0" && "$capacity" == "0" ]]; then
    test_pass "Set capacity to 0 clears list"
else
    test_fail "Count=$count (expected 0), Capacity=$capacity (expected 0)"
fi

# Test: Increase capacity on empty list
test_start "Increase capacity on empty list"
mylist.SetCapacity 20
capacity=$(mylist.Capacity)
count=$(mylist.Count)
if [[ "$capacity" == "20" && "$count" == "0" ]]; then
    test_pass "Increased capacity on empty list"
else
    test_fail "Capacity=$capacity (expected 20), Count=$count (expected 0)"
fi

# Cleanup
mylist.delete

test_info "006_capacity_operations.sh completed"
