#!/bin/bash
# 004_delete_operations.sh - Test Delete method

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Initialize test-specific temp directory
init_test_tmpdir "004"

test_section "004: Delete Operations"

# Create TList instance and add items
TList.new mylist
mylist.Add "item0"
mylist.Add "item1"
mylist.Add "item2"
mylist.Add "item3"
mylist.Add "item4"

# Test: Delete from middle
test_start "Delete from middle"
mylist.Delete 2
count=$(mylist.Count)
if [[ "$count" == "4" ]]; then
    items_var="mylist_items"
    declare -n items_ref="$items_var"
    # Should now be: item0, item1, item3, item4
    if [[ "${items_ref[2]}" == "item3" ]]; then
        test_pass "Deleted from middle correctly"
    else
        test_fail "Item at index 2 is '${items_ref[2]}', expected 'item3'"
    fi
else
    test_fail "Count is $count, expected 4"
fi

# Test: Delete from beginning
test_start "Delete from beginning"
mylist.Delete 0
count=$(mylist.Count)
first=$(mylist.First)
if [[ "$count" == "3" && "$first" == "item1" ]]; then
    test_pass "Deleted from beginning correctly"
else
    test_fail "Count: $count (expected 3), First: '$first' (expected 'item1')"
fi

# Test: Delete from end
test_start "Delete from end"
mylist.Delete 2  # Last index now
count=$(mylist.Count)
last=$(mylist.Last)
if [[ "$count" == "2" && "$last" == "item3" ]]; then
    test_pass "Deleted from end correctly"
else
    test_fail "Count: $count (expected 2), Last: '$last' (expected 'item3')"
fi

# Test: Delete invalid index (should handle gracefully)
test_start "Delete invalid index"
mylist.Delete 10 2>/dev/null  # Out of bounds
result=$?
if [[ $result -ne 0 ]]; then
    test_pass "Delete invalid index handled gracefully"
else
    test_fail "Delete invalid index should return error"
fi

# Test: Delete negative index
test_start "Delete negative index"
mylist.Delete -1 2>/dev/null
result=$?
if [[ $result -ne 0 ]]; then
    test_pass "Delete negative index handled gracefully"
else
    test_fail "Delete negative index should return error"
fi

# Cleanup
mylist.delete

test_info "004_delete_operations.sh completed"
