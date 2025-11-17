#!/bin/bash
# 012_IntegrationAndComplexScenarios.sh - Integration tests and complex scenarios
# Tests complex workflows combining multiple operations

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "012"

test_section "012: Integration and Complex Scenarios"

# Test: Build sorted list from unsorted data
test_start "Build sorted list from unsorted data"
TStringList.new mylist
for fruit in "mango" "apple" "cherry" "banana" "date"; do
    mylist.Add "$fruit" >/dev/null
done
mylist.Sort
items_ordered="true"
for i in {0..4}; do
    item=$(mylist.Get $i)
    # Just verify we can get all items after sort
done
if [[ "$(mylist.sorted)" == "true" && "$(mylist.count)" == "5" ]]; then
    test_pass "Unsorted list sorted and still has all items"
else
    test_fail "Sort failed: sorted=$(mylist.sorted), count=$(mylist.count)"
fi

# Test: Find-Add workflow
test_start "Find item, then add related items"
TStringList.new list
list.Add "apple"
list.Add "banana"
list.Add "cherry"
index=$(list.IndexOf "banana")
if [[ "$index" == "1" ]]; then
    list.Add "apricot"
    list.Sort
    test_pass "Found and sorted list successfully"
else
    test_fail "Could not find banana"
fi

# Test: Copy and modify
test_start "Copy list and modify independently"
TStringList.new original
original.Add "first"
original.Add "second"
original.Add "third"
TStringList.new copy
copy.AddStrings "$original"
copy.Put 0 "changed"
orig_item=$(original.Get 0)
copy_item=$(copy.Get 0)
if [[ "$orig_item" == "first" && "$copy_item" == "changed" ]]; then
    test_pass "Copy and modify independent"
else
    test_fail "orig=$orig_item, copy=$copy_item"
fi
original.delete
copy.delete

# Test: Remove while iterating (simulated)
test_start "Remove multiple items"
TStringList.new mylist
mylist.Add "keep1"
mylist.Add "remove1"
mylist.Add "keep2"
mylist.Add "remove2"
mylist.Add "keep3"
mylist.Remove "remove1"
mylist.Remove "remove2"
count=$(mylist.count)
items_correct="true"
if [[ "$(mylist.Get 0)" != "keep1" ]]; then items_correct="false"; fi
if [[ "$(mylist.Get 1)" != "keep2" ]]; then items_correct="false"; fi
if [[ "$(mylist.Get 2)" != "keep3" ]]; then items_correct="false"; fi
if [[ "$count" == "3" && "$items_correct" == "true" ]]; then
    test_pass "Multiple removes maintain correct items"
else
    test_fail "Count=$count, items_correct=$items_correct"
fi
mylist.delete

# Test: Case-sensitive to case-insensitive transition
test_start "Switch case sensitivity"
TStringList.new mylist
mylist.Add "ABC"
mylist.case_sensitive = "true"
index1=$(mylist.IndexOf "abc")
mylist.case_sensitive = "false"
index2=$(mylist.IndexOf "abc")
if [[ "$index1" == "-1" && "$index2" == "0" ]]; then
    test_pass "Case sensitivity switch affects search correctly"
else
    test_fail "case_sensitive=$index1, case_insensitive=$index2"
fi
mylist.delete

# Test: Sorted list workflow
test_start "Sorted list complete workflow"
TStringList.new mylist
mylist.sorted = "true"
mylist.duplicates = "dupIgnore"
# Add items in random order, should maintain sort
for item in "grape" "apple" "cherry" "apple" "banana"; do
    mylist.Add "$item" >/dev/null
done
count=$(mylist.count)
first=$(mylist.Get 0)
if [[ "$count" == "4" && "$first" == "apple" ]]; then
    test_pass "Sorted list maintained order, duplicate ignored"
else
    test_fail "count=$count (expected 4), first=$first (expected apple)"
fi
mylist.delete

# Test: Large list operations
test_start "Large list operations"
TStringList.new mylist
# Add 500 items
for i in {1..500}; do
    mylist.Add "item_$i" >/dev/null
done
count=$(mylist.count)
first=$(mylist.Get 0)
last=$(mylist.Get 499)
mylist.Sort
first_sorted=$(mylist.Get 0)
if [[ "$count" == "500" && "$first" == "item_1" && "$last" == "item_500" ]]; then
    test_pass "Large list (500 items) operations work correctly"
else
    test_fail "count=$count, first=$first, last=$last"
fi
mylist.delete

# Test: Stress test - rapid operations
test_start "Stress test - rapid operations"
TStringList.new mylist
for i in {1..100}; do
    mylist.Add "item$i" >/dev/null
done
for i in {1..50}; do
    mylist.Remove "item$i" >/dev/null
done
count=$(mylist.count)
if [[ "$count" == "50" ]]; then
    test_pass "Stress test passed (add 100, remove 50)"
else
    test_fail "count=$count, expected 50"
fi
mylist.delete

# Test: Clear and reuse
test_start "Clear and reuse list multiple times"
TStringList.new mylist
for cycle in {1..3}; do
    mylist.Add "cycle${cycle}_item1"
    mylist.Add "cycle${cycle}_item2"
    count=$(mylist.count)
    if [[ "$count" != "2" ]]; then
        break
    fi
    mylist.Clear
done
if [[ "$count" == "2" ]]; then
    test_pass "Clear and reuse works multiple times"
else
    test_fail "count=$count, expected 2"
fi
mylist.delete

# Test: Complex property combination
test_start "Complex property combination workflow"
TStringList.new mylist
mylist.case_sensitive = "false"
mylist.sorted = "true"
mylist.duplicates = "dupIgnore"
for item in "Zebra" "apple" "BANANA" "cherry" "apple"; do
    mylist.Add "$item" >/dev/null
done
count=$(mylist.count)
first=$(mylist.Get 0)
# Should have 4 items (one duplicate ignored) and first should be "apple"
if [[ "$count" == "4" && "$first" == "apple" ]]; then
    test_pass "Complex property combination works"
else
    test_fail "count=$count (expected 4), first=$first (expected apple)"
fi
mylist.delete

test_info "012_IntegrationAndComplexScenarios.sh completed"
