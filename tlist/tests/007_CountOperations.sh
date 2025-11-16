#!/bin/bash
# 007_count_operations.sh - Test count property and _setCount method

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "007"

test_section "007: Count Operations"

# Create TList instance
TList.new mylist

# Test: Initial count
test_start "Initial count"
count=$(mylist.count)
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
count=$(mylist.count)
if [[ "$count" == "5" ]]; then
    test_pass "Count is 5 after adding 5 items"
else
    test_fail "Count is $count, expected 5"
fi

# Test: count assignment to increase (add nil items)
test_start "count assignment to increase"
mylist.count = "10"
count=$(mylist.count)
capacity=$(mylist.capacity)
if [[ "$count" == "10" && "$capacity" -ge "10" ]]; then
    test_pass "count assignment increased to 10"
else
    test_fail "Count=$count (expected 10), Capacity=$capacity (expected >=10)"
fi

# Test: Check that new items are empty/nil
test_start "New items from count assignment are empty"
items_var="mylist_items"
declare -n items_ref="$items_var"
if [[ "${items_ref[5]}" == "" && "${items_ref[9]}" == "" ]]; then
    test_pass "New items from count assignment are empty"
else
    test_fail "New items not empty: index 5='${items_ref[5]}', index 9='${items_ref[9]}'"
fi

# Test: count assignment to decrease (truncate)
test_start "count assignment to decrease"
mylist.count = "3"
count=$(mylist.count)
if [[ "$count" == "3" ]]; then
    test_pass "count assignment decreased to 3"
else
    test_fail "Count is $count, expected 3"
fi

# Test: count assignment to 0
test_start "count assignment to 0"
mylist.count = "0"
count=$(mylist.count)
if [[ "$count" == "0" ]]; then
    test_pass "count assignment to 0 clears list"
else
    test_fail "Count is $count, expected 0"
fi

# Test: count assignment on empty list
test_start "count assignment on empty list"
mylist.count = "5"
count=$(mylist.count)
capacity=$(mylist.capacity)
if [[ "$count" == "5" && "$capacity" -ge "5" ]]; then
    test_pass "count assignment to 5 on empty list"
else
    test_fail "Count=$count (expected 5), Capacity=$capacity (expected >=5)"
fi

# Cleanup
mylist.delete

test_info "007_count_operations.sh completed"
