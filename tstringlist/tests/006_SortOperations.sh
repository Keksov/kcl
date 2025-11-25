#!/bin/bash
# 006_SortOperations.sh - Test Sort method and sorted list operations
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

kk_test_section "006: Sort Operations"

# Create unsorted TStringList
TStringList.new mylist
mylist.Add "cherry"
mylist.Add "apple"
mylist.Add "elderberry"
mylist.Add "banana"
mylist.Add "date"

# Test: Initial state is unsorted
kk_test_start "Verify initial list is unsorted"
if [[ "$(mylist.sorted)" == "false" ]]; then
    kk_test_pass "List is initially unsorted"
else
    kk_test_fail "List should be unsorted initially"
fi

# Test: Verify order before sort
kk_test_start "Verify original order before sort"
item0=$(mylist.Get 0)
item1=$(mylist.Get 1)
if [[ "$item0" == "cherry" && "$item1" == "apple" ]]; then
    kk_test_pass "Original order verified: cherry, apple, ..."
else
    kk_test_fail "Expected cherry, apple; got '$item0', '$item1'"
fi

# Test: Sort the list
kk_test_start "Sort the list"
mylist.Sort
sorted=$(mylist.sorted)
if [[ "$sorted" == "true" ]]; then
    kk_test_pass "List sorted successfully"
else
    kk_test_fail "List should be marked as sorted"
fi

# Test: Verify sorted order (case-insensitive)
kk_test_start "Verify sorted order after sort"
item0=$(mylist.Get 0)
item1=$(mylist.Get 1)
item2=$(mylist.Get 2)
item3=$(mylist.Get 3)
item4=$(mylist.Get 4)
# Expected order: apple, banana, cherry, date, elderberry
if [[ "$item0" == "apple" && "$item1" == "banana" && "$item2" == "cherry" ]]; then
    kk_test_pass "List sorted in correct order"
else
    kk_test_fail "Expected apple, banana, cherry; got '$item0', '$item1', '$item2'"
fi

# Test: Find method on sorted list
kk_test_start "Find on sorted list"
mylist.Find "date"
index=$RESULT
if [[ "$index" == "3" ]]; then
    kk_test_pass "Find returned correct index 3 for 'date'"
else
    kk_test_fail "Find returned $index, expected 3"
fi

# Test: Find non-existent item (returns negative insertion point)
kk_test_start "Find non-existent item returns insertion point"
mylist.Find "aardvark"
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kk_test_pass "Find returned -1 (insertion point for first position)"
else
    kk_test_fail "Find returned $result, expected -1"
fi

# Test: Sort with mixed case
kk_test_start "Sort with mixed case strings"
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
    kk_test_pass "Mixed case list sorted correctly"
else
    kk_test_fail "Sorted order incorrect: '$item0', '$item1', '$item2', '$item3'"
fi
mixedlist.delete

# Test: Case-sensitive sort
kk_test_start "Case-sensitive sort"
TStringList.new caselist
caselist.case_sensitive = "true"
caselist.Add "zebra"
caselist.Add "Apple"
caselist.Add "banana"
caselist.Sort
item0=$(caselist.Get 0)
item1=$(caselist.Get 1)
item2=$(caselist.Get 2)
# Case-sensitive ASCII order: Apple, banana, zebra (uppercase before lowercase)
if [[ "$item0" == "Apple" && "$item1" == "banana" && "$item2" == "zebra" ]]; then
    kk_test_pass "Case-sensitive sort works correctly"
else
    kk_test_fail "Case-sensitive sort incorrect: '$item0', '$item1', '$item2'"
fi
caselist.delete

# Test: Single element list
kk_test_start "Sort single element list"
TStringList.new singlelist
singlelist.Add "only"
singlelist.Sort
item=$(singlelist.Get 0)
if [[ "$item" == "only" && "$(singlelist.sorted)" == "true" ]]; then
    kk_test_pass "Single element list sorted successfully"
else
    kk_test_fail "Single element sort failed"
fi
singlelist.delete

# Test: Empty list sort
kk_test_start "Sort empty list"
TStringList.new emptylist
emptylist.Sort
count=$(emptylist.count)
if [[ "$count" == "0" && "$(emptylist.sorted)" == "true" ]]; then
    kk_test_pass "Empty list marked as sorted with count 0"
else
    kk_test_fail "Empty list sort failed"
fi
emptylist.delete

# Cleanup
mylist.delete

kk_test_log "006_SortOperations.sh completed"
