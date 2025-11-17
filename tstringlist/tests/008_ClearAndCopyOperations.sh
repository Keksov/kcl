#!/bin/bash
# 008_ClearAndCopyOperations.sh - Test Clear and Assign operations
# Tests clearing lists and copying list contents

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "008"

test_section "008: Clear and Copy Operations"

# Create a list with data
TStringList.new mylist
mylist.Add "apple"
mylist.Add "banana"
mylist.Add "cherry"
mylist.Add "date"
mylist.Add "elderberry"

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
mylist.Add "fig"
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

# Test: Clear with different properties
test_start "Clear respects properties"
mylist.sorted = "true"
mylist.case_sensitive = "true"
mylist.duplicates = "dupError"
mylist.Clear
sorted=$(mylist.sorted)
# Properties should be preserved after clear
if [[ "$sorted" == "true" ]]; then
    test_pass "Properties preserved after clear"
else
    test_fail "Properties not preserved"
fi

# Test: AddStrings from one list to another
test_start "AddStrings from another list"
TStringList.new source
source.Add "item1"
source.Add "item2"
source.Add "item3"
mylist.Clear
mylist.AddStrings "$source"
count=$(mylist.count)
item0=$(mylist.Get 0)
item2=$(mylist.Get 2)
if [[ "$count" == "3" && "$item0" == "item1" && "$item2" == "item3" ]]; then
    test_pass "AddStrings copied all items"
else
    test_fail "Copy failed: count=$count, items='$item0' '$item2'"
fi
source.delete

# Test: AddStrings to non-empty list
test_start "AddStrings appends to non-empty list"
TStringList.new source2
source2.Add "new1"
source2.Add "new2"
count_before=$(mylist.count)
mylist.AddStrings "$source2"
count_after=$(mylist.count)
item=$(mylist.Get 5)  # Should be new1 at index 5
if [[ "$count_after" == "5" && "$item" == "new1" ]]; then
    test_pass "AddStrings appended correctly"
else
    test_fail "Count: $count_after (expected 5), Item at 5: '$item'"
fi
source2.delete

# Test: AddStrings from empty list
test_start "AddStrings from empty list"
TStringList.new empty_source
count_before=$(mylist.count)
mylist.AddStrings "$empty_source"
count_after=$(mylist.count)
if [[ "$count_after" == "$count_before" ]]; then
    test_pass "AddStrings from empty list did nothing"
else
    test_fail "Count changed: before=$count_before, after=$count_after"
fi
empty_source.delete

# Test: AddStrings with duplicates
test_start "AddStrings with overlapping items"
TStringList.new dup_source
dup_source.Add "item1"
dup_source.Add "item2"
dup_source.Add "item2"  # Duplicate
count_before=$(mylist.count)
mylist.AddStrings "$dup_source"
count_after=$(mylist.count)
# Should have added 3 items
if [[ "$count_after" == "$((count_before + 3))" ]]; then
    test_pass "AddStrings added all items including duplicates"
else
    test_fail "Count: before=$count_before, after=$count_after (expected $((count_before + 3)))"
fi
dup_source.delete

# Test: Clear large list
test_start "Clear large list"
TStringList.new largelist
for i in {1..1000}; do
    largelist.Add "item$i" >/dev/null
done
count_before=$(largelist.count)
largelist.Clear
count_after=$(largelist.count)
if [[ "$count_before" == "1000" && "$count_after" == "0" ]]; then
    test_pass "Large list cleared successfully"
else
    test_fail "Before: $count_before, After: $count_after"
fi
largelist.delete

# Cleanup
mylist.delete

test_info "008_ClearAndCopyOperations.sh completed"
