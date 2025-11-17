#!/bin/bash
# 006_SortOperations.sh - Test Sort method and sorted list operations
# Tests sorting strings and maintaining sorted order

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "006"

test_section "006: Sort Operations"

# Create unsorted TStringList
TStringList.new mylist
mylist.Add "cherry"
mylist.Add "apple"
mylist.Add "elderberry"
mylist.Add "banana"
mylist.Add "date"

# Test: Initial state is unsorted
test_start "Verify initial list is unsorted"
if [[ "$(mylist.sorted)" == "false" ]]; then
    test_pass "List is initially unsorted"
else
    test_fail "List should be unsorted initially"
fi

# Test: Verify order before sort
test_start "Verify original order before sort"
item0=$(mylist.Get 0)
item1=$(mylist.Get 1)
if [[ "$item0" == "cherry" && "$item1" == "apple" ]]; then
    test_pass "Original order verified: cherry, apple, ..."
else
    test_fail "Expected cherry, apple; got '$item0', '$item1'"
fi

# Test: Sort the list
test_start "Sort the list"
mylist.Sort
sorted=$(mylist.sorted)
if [[ "$sorted" == "true" ]]; then
    test_pass "List sorted successfully"
else
    test_fail "List should be marked as sorted"
fi

# Test: Verify sorted order (case-insensitive)
test_start "Verify sorted order after sort"
item0=$(mylist.Get 0)
item1=$(mylist.Get 1)
item2=$(mylist.Get 2)
item3=$(mylist.Get 3)
item4=$(mylist.Get 4)
# Expected order: apple, banana, cherry, date, elderberry
if [[ "$item0" == "apple" && "$item1" == "banana" && "$item2" == "cherry" ]]; then
    test_pass "List sorted in correct order"
else
    test_fail "Expected apple, banana, cherry; got '$item0', '$item1', '$item2'"
fi

# Test: Find method on sorted list
test_start "Find on sorted list"
index=$(mylist.Find "date")
if [[ "$index" == "3" ]]; then
    test_pass "Find returned correct index 3 for 'date'"
else
    test_fail "Find returned $index, expected 3"
fi

# Test: Find non-existent item (returns negative insertion point)
test_start "Find non-existent item returns insertion point"
result=$(mylist.Find "aardvark")
if [[ "$result" == "-1" ]]; then
    test_pass "Find returned -1 (insertion point for first position)"
else
    test_fail "Find returned $result, expected -1"
fi

# Test: Sort with mixed case
test_start "Sort with mixed case strings"
TStringList.new mixedlist
mixedlist.Add "Zebra"
mixedlist.Add "apple"
mixedlist.Add "BANANA"
mixedlist.Add "cherry"
mixedlist.Sort
item0=$(mixedlist.Get 0)
item1=$(mixedlist.Get 1)
item2=$(mixedlist.Get 2)
item3=$(mixedlist.Get 3)
# Case-insensitive default, so: apple, BANANA, cherry, Zebra
if [[ "$item0" == "apple" && "$item1" == "BANANA" && "$item2" == "cherry" && "$item3" == "Zebra" ]]; then
    test_pass "Mixed case list sorted correctly"
else
    test_fail "Sorted order incorrect: '$item0', '$item1', '$item2', '$item3'"
fi
mixedlist.delete

# Test: Case-sensitive sort
test_start "Case-sensitive sort"
TStringList.new caselist
caselist.case_sensitive = "true"
caselist.Add "zebra"
caselist.Add "Apple"
caselist.Add "banana"
caselist.Sort
item0=$(caselist.Get 0)
item1=$(caselist.Get 1)
item2=$(caselist.Get 2)
item3=$(caselist.Get 3)
# Case-sensitive ASCII order: Apple, banana, zebra (uppercase before lowercase)
if [[ "$item0" == "Apple" ]]; then
    test_pass "Case-sensitive sort works correctly"
else
    test_fail "First item is '$item0', expected 'Apple'"
fi
caselist.delete

# Test: Single element list
test_start "Sort single element list"
TStringList.new singlelist
singlelist.Add "only"
singlelist.Sort
item=$(singlelist.Get 0)
if [[ "$item" == "only" && "$(singlelist.sorted)" == "true" ]]; then
    test_pass "Single element list sorted successfully"
else
    test_fail "Single element sort failed"
fi
singlelist.delete

# Test: Empty list sort
test_start "Sort empty list"
TStringList.new emptylist
emptylist.Sort
count=$(emptylist.count)
if [[ "$count" == "0" && "$(emptylist.sorted)" == "true" ]]; then
    test_pass "Empty list marked as sorted with count 0"
else
    test_fail "Empty list sort failed"
fi
emptylist.delete

# Cleanup
mylist.delete

test_info "006_SortOperations.sh completed"
