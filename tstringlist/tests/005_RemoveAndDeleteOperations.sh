#!/bin/bash
# 005_RemoveAndDeleteOperations.sh - Test Remove and Delete operations
# Tests removing strings from the list by value and by index

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "005"

test_section "005: Remove and Delete Operations"

# Create TStringList with test data
TStringList.new mylist
mylist.Add "apple"
mylist.Add "banana"
mylist.Add "cherry"
mylist.Add "date"
mylist.Add "elderberry"

# Test: Remove by value (apple)
test_start "Remove string by value"
mylist.Remove "apple"
index=$RESULT
count=$(mylist.count)
if [[ "$index" == "0" && "$count" == "4" ]]; then
    test_pass "Remove 'apple' succeeded, count is now 4"
else
    test_fail "Remove returned $index (expected 0), count is $count (expected 4)"
fi

# Test: Verify apple was removed
test_start "Verify removed string is gone"
item=$(mylist.Get 0)
if [[ "$item" == "banana" ]]; then
    test_pass "apple was removed, banana is now at index 0"
else
    test_fail "Get(0) returned '$item', expected 'banana'"
fi

# Test: Remove non-existent string
test_start "Remove non-existent string"
mylist.Remove "grape"
index=$RESULT
if [[ "$index" == "-1" ]]; then
    test_pass "Remove non-existent string returned -1"
else
    test_fail "Remove returned $index, expected -1"
fi

# Test: Count unchanged after failed remove
test_start "Count unchanged after failed remove"
count=$(mylist.count)
if [[ "$count" == "4" ]]; then
    test_pass "Count remained 4 after failed remove"
else
    test_fail "Count is $count, expected 4"
fi

# Recreate with fresh data for Delete tests
TStringList.new dellist
dellist.Add "one"
dellist.Add "two"
dellist.Add "three"
dellist.Add "four"
dellist.Add "five"

# Test: Delete at index 0
test_start "Delete at index 0"
dellist.Delete 0
count=$(dellist.count)
item=$(dellist.Get 0)
if [[ "$count" == "4" && "$item" == "two" ]]; then
    test_pass "Delete(0) removed first item, 'two' now at index 0"
else
    test_fail "Count: $count (expected 4), item: '$item' (expected 'two')"
fi

# Test: Delete at middle index
test_start "Delete at middle index"
dellist.Delete 1  # Remove "three"
count=$(dellist.count)
item=$(dellist.Get 1)
if [[ "$count" == "3" && "$item" == "four" ]]; then
    test_pass "Delete(1) removed middle item"
else
    test_fail "Count: $count (expected 3), item: '$item' (expected 'four')"
fi

# Test: Delete at last index
test_start "Delete at last index"
dellist.Delete 2  # Remove "five"
count=$(dellist.count)
if [[ "$count" == "2" ]]; then
    test_pass "Delete(2) removed last item, count is now 2"
else
    test_fail "Count is $count, expected 2"
fi

# Test: Delete with invalid index (negative)
test_start "Delete with invalid index (negative)"
TRAP_ERRORS_ENABLED=false
dellist.Delete -1 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    test_pass "Delete(-1) correctly failed"
else
    test_fail "Delete(-1) should have failed"
fi

# Test: Delete with invalid index (out of bounds)
test_start "Delete with invalid index (out of bounds)"
TRAP_ERRORS_ENABLED=false
dellist.Delete 100 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    test_pass "Delete(100) correctly failed"
else
    test_fail "Delete(100) should have failed"
fi

# Test: Delete all remaining items
test_start "Delete all remaining items"
dellist.Delete 0
dellist.Delete 0
count=$(dellist.count)
if [[ "$count" == "0" ]]; then
    test_pass "All items deleted, count is 0"
else
    test_fail "Count is $count, expected 0"
fi

# Test: Remove with duplicates
test_start "Remove with duplicate strings"
TStringList.new duplist
duplist.Add "item"
duplist.Add "item"
duplist.Add "item"
count_before=$(duplist.count)
duplist.Remove "item"
index=$RESULT
count_after=$(duplist.count)
if [[ "$count_before" == "3" && "$index" == "0" && "$count_after" == "2" ]]; then
    test_pass "Remove removed first occurrence of duplicates"
else
    test_fail "Before: $count_before, After: $count_after, Index: $index"
fi
duplist.delete

# Cleanup
mylist.delete
dellist.delete

test_info "005_RemoveAndDeleteOperations.sh completed"
