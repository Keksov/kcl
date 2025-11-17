#!/bin/bash
# 008_ClearAndCopyOperations.sh - Test Clear and Copy operations
# Tests clearing lists and basic list operations

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "008"

test_section "008: Clear and Copy Operations"

# Create a list with data
TStringList.new mylist
mylist.Add "apple" >/dev/null
mylist.Add "banana" >/dev/null
mylist.Add "cherry" >/dev/null
mylist.Add "date" >/dev/null
mylist.Add "elderberry" >/dev/null

# Test: Count before clear
test_start "Verify list has data before clear"
count=$(mylist.count)
if [[ "$count" == "5" ]]; then
    test_pass "List has 5 items before clear"
else
    test_fail "Count is $count, expected 5"
fi

# Test: Clear the list
test_start "Clear the list"
mylist.Clear
count=$(mylist.count)
if [[ "$count" == "0" ]]; then
    test_pass "List cleared successfully, count is 0"
else
    test_fail "Count is $count, expected 0"
fi

# Test: Capacity after clear
test_start "Capacity after clear"
capacity=$(mylist.capacity)
if [[ "$capacity" == "0" ]]; then
    test_pass "Capacity is 0 after clear"
else
    test_fail "Capacity is $capacity, expected 0"
fi

# Test: Can add to cleared list
test_start "Add to cleared list"
mylist.Add "fig" >/dev/null
count=$(mylist.count)
item=$(mylist.Get 0)
if [[ "$count" == "1" && "$item" == "fig" ]]; then
    test_pass "Successfully added to cleared list"
else
    test_fail "Count: $count (expected 1), Item: '$item'"
fi

# Test: Clear empty list (should not error)
test_start "Clear empty list"
mylist.Clear
count=$(mylist.count)
if [[ "$count" == "0" ]]; then
    test_pass "Clear on empty list succeeded"
else
    test_fail "Count is $count, expected 0"
fi

# Test: Clear respects other properties
test_start "Properties preserved after clear"
mylist.case_sensitive = "true"
mylist.duplicates = "dupError"
mylist.Clear
case_sensitive=$(mylist.case_sensitive)
if [[ "$case_sensitive" == "true" ]]; then
    test_pass "Properties preserved after clear"
else
    test_fail "Properties not preserved"
fi

# Test: Clear large list
test_start "Clear large list"
TStringList.new largelist
for i in {1..100}; do
    largelist.Add "item$i" >/dev/null
done
count_before=$(largelist.count)
largelist.Clear
count_after=$(largelist.count)
if [[ "$count_before" == "100" && "$count_after" == "0" ]]; then
    test_pass "Large list cleared successfully"
else
    test_fail "Before: $count_before, After: $count_after"
fi
largelist.delete

# Cleanup
mylist.delete

test_info "008_ClearAndCopyOperations.sh completed"
