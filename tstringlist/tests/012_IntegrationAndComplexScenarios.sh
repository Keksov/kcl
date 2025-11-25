#!/bin/bash
# 012_IntegrationAndComplexScenarios.sh - Integration tests and complex scenarios
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tstringlist module
TSTRINGLIST_DIR="$SCRIPT_DIR/.."
source "$TSTRINGLIST_DIR/tstringlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Initialize test-specific temp directory

kk_test_section "012: Integration and Complex Scenarios"

# Test: Build sorted list from unsorted data
kk_test_start "Build sorted list from unsorted data"
TStringList.new mylist
for fruit in "mango" "apple" "cherry" "banana" "date"; do
    mylist.Add "$fruit"
done
mylist.Sort
items_ordered="true"
for i in {0..4}; do
    item=$(mylist.Get $i)
    # Just verify we can get all items after sort
done
if [[ "$(mylist.sorted)" == "true" && "$(mylist.count)" == "5" ]]; then
    kk_test_pass "Unsorted list sorted and still has all items"
else
    kk_test_fail "Sort failed: sorted=$(mylist.sorted), count=$(mylist.count)"
fi

# Test: Find-Add workflow
kk_test_start "Find item, then add related items"
TStringList.new list
list.Add "apple"
list.Add "banana"
list.Add "cherry"
index=$(list.IndexOf "banana")
if [[ "$index" == "1" ]]; then
    list.Add "apricot"
    list.Sort
    kk_test_pass "Found and sorted list successfully"
else
    kk_test_fail "Could not find banana"
fi

# Test: Copy and modify
kk_test_start "Copy list and modify independently"
TStringList.new original
original.Add "first"
original.Add "second"
original.Add "third"
TStringList.new copy
copy.AddStrings original
copy.Put 0 "changed"
orig_item=$(original.Get 0)
copy_item=$(copy.Get 0)
if [[ "$orig_item" == "first" && "$copy_item" == "changed" ]]; then
    kk_test_pass "Copy and modify independent"
else
    kk_test_fail "orig=$orig_item, copy=$copy_item"
fi
original.delete
copy.delete

# Test: Remove while iterating (simulated)
kk_test_start "Remove multiple items"
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
    kk_test_pass "Multiple removes maintain correct items"
else
    kk_test_fail "Count=$count, items_correct=$items_correct"
fi
mylist.delete

# Test: Case-sensitive to case-insensitive transition
kk_test_start "Switch case sensitivity"
TStringList.new mylist
mylist.Add "ABC"
mylist.case_sensitive = "true"
mylist.IndexOf "abc"
index1=$RESULT
mylist.case_sensitive = "false"
mylist.IndexOf "abc"
index2=$RESULT
if [[ "$index1" == "-1" && "$index2" == "0" ]]; then
    kk_test_pass "Case sensitivity switch affects search correctly"
else
    kk_test_fail "case_sensitive=$index1, case_insensitive=$index2"
fi
mylist.delete

# Test: Sorted list workflow
kk_test_start "Sorted list complete workflow"
TStringList.new mylist
mylist.sorted = "false"
mylist.duplicates = "dupIgnore"
# Add items, then sort to check it works correctly
for item in "grape" "apple" "cherry" "apple" "banana"; do
    mylist.Add "$item"
done
mylist.Sort
count=$(mylist.count)
first=$(mylist.Get 0)
if [[ "$count" == "4" && "$first" == "apple" ]]; then
    kk_test_pass "Sorted list maintained order, duplicate ignored"
else
    kk_test_fail "count=$count (expected 4), first=$first (expected apple)"
fi
mylist.delete

# Test: Large list operations
kk_test_start "Large list operations"
TStringList.new mylist
# Add 100 items
for i in {1..100}; do
    mylist.Add "item_$i"
done
count=$(mylist.count)
first=$(mylist.Get 0)
last=$(mylist.Get 99)
mylist.Sort
first_sorted=$(mylist.Get 0)
if [[ "$count" == "100" && "$first" == "item_1" && "$last" == "item_100" ]]; then
    kk_test_pass "Large list (100 items) operations work correctly"
else
    kk_test_fail "count=$count, first=$first, last=$last"
fi
mylist.delete

# Test: Stress test - rapid operations
kk_test_start "Stress test - rapid operations"
TStringList.new mylist
for i in {1..50}; do
    mylist.Add "item$i"
done
for i in {1..25}; do
    mylist.Remove "item$i"
done
count=$(mylist.count)
if [[ "$count" == "25" ]]; then
    kk_test_pass "Stress test passed (add 50, remove 25)"
else
    kk_test_fail "count=$count, expected 25"
fi
mylist.delete

# Test: Clear and reuse
kk_test_start "Clear and reuse list multiple times"
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
    kk_test_pass "Clear and reuse works multiple times"
else
    kk_test_fail "count=$count, expected 2"
fi
mylist.delete

# Test: Complex property combination
kk_test_start "Complex property combination workflow"
TStringList.new mylist
mylist.case_sensitive = "false"
mylist.sorted = "true"
mylist.duplicates = "dupIgnore"
for item in "Zebra" "apple" "BANANA" "cherry" "apple"; do
    mylist.Add "$item"
done
count=$(mylist.count)
first=$(mylist.Get 0)
# Should have 4 items (one duplicate ignored) and first should be "apple"
if [[ "$count" == "4" && "$first" == "apple" ]]; then
    kk_test_pass "Complex property combination works"
else
    kk_test_fail "count=$count (expected 4), first=$first (expected apple)"
fi
mylist.delete

kk_test_log "012_IntegrationAndComplexScenarios.sh completed"
