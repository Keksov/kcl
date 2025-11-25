#!/bin/bash
# 007_SortedListOperations.sh - Test Add operations on sorted lists
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

kk_test_section "007: Sorted List Add Operations"

# Create and setup a sorted list
TStringList.new mylist
mylist.sorted = "true"
mylist.duplicates = "dupAccept"

# Test: Add to empty sorted list
kk_test_start "Add to empty sorted list"
mylist.Add "banana"
count=$(mylist.count)
item=$(mylist.Get 0)
if [[ "$count" == "1" && "$item" == "banana" ]]; then
    kk_test_pass "Added to sorted list successfully"
else
    kk_test_fail "Count: $count (expected 1), Item: '$item'"
fi

# Test: Add maintains sort order (insert before)
kk_test_start "Add maintains sort order (insert before)"
mylist.Add "apple"
item0=$(mylist.Get 0)
item1=$(mylist.Get 1)
if [[ "$item0" == "apple" && "$item1" == "banana" ]]; then
    kk_test_pass "Apple inserted before banana"
else
    kk_test_fail "Expected apple, banana; got '$item0', '$item1'"
fi

# Test: Add maintains sort order (insert after)
kk_test_start "Add maintains sort order (insert after)"
mylist.Add "cherry"
item2=$(mylist.Get 2)
if [[ "$item2" == "cherry" ]]; then
    kk_test_pass "Cherry inserted after banana"
else
    kk_test_fail "Item at index 2: '$item2' (expected 'cherry')"
fi

# Test: Add duplicate with dupAccept
kk_test_start "Add duplicate with dupAccept"
mylist.Add "banana"
count=$(mylist.count)
items=$(mylist.Get 1 && echo ";" && mylist.Get 2)
if [[ "$count" == "4" ]]; then
    kk_test_pass "Duplicate banana accepted, count is 4"
else
    kk_test_fail "Count: $count (expected 4)"
fi

# Test: Add duplicate with dupIgnore
kk_test_start "Add duplicate with dupIgnore"
TStringList.new ignorelist
ignorelist.sorted = "true"
ignorelist.duplicates = "dupIgnore"
ignorelist.Add "apple"
ignorelist.Add "banana"
ignorelist.Add "cherry"
result=$(ignorelist.Add "banana")
count=$(ignorelist.count)
if [[ "$count" == "3" ]]; then
    kk_test_pass "Duplicate banana ignored, count remained 3"
else
    kk_test_fail "Count: $count (expected 3)"
fi
ignorelist.delete

# Test: Add duplicate with dupError
kk_test_start "Add duplicate with dupError (should fail)"
TStringList.new errorlist
errorlist.sorted = "true"
errorlist.duplicates = "dupError"
errorlist.Add "apple"
errorlist.Add "banana"
TRAP_ERRORS_ENABLED=false
errorlist.Add "banana" 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kk_test_pass "Duplicate banana raised error"
else
    kk_test_fail "Should have raised error for duplicate"
fi
errorlist.delete

# Test: Insert into sorted list should fail
kk_test_start "Insert into sorted list should fail"
TStringList.new sortedlist
sortedlist.sorted = "true"
sortedlist.Add "apple"
TRAP_ERRORS_ENABLED=false
sortedlist.Insert 0 "something" 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kk_test_pass "Insert correctly failed on sorted list"
else
    kk_test_fail "Insert should have failed on sorted list"
fi
sortedlist.delete

# Test: Find on non-empty sorted list
kk_test_start "Find on non-empty sorted list"
mylist.Find "banana"
result=$RESULT
if [[ "$result" == "1" ]]; then
    kk_test_pass "Find returned correct index 1 for 'banana'"
else
    kk_test_fail "Find returned $result, expected 1"
fi

# Test: Find insertion point for new item
kk_test_start "Find insertion point for non-existent item"
mylist.Find "blueberry"
result=$RESULT
# Should return negative insertion point
if [[ "$result" -lt "0" ]]; then
    kk_test_pass "Find returned negative value (insertion point)"
else
    kk_test_fail "Find returned $result, expected negative value"
fi

# Test: Add many items to sorted list maintains order
kk_test_start "Add many items to sorted list"
TStringList.new biglist
biglist.sorted = "true"
biglist.duplicates = "dupAccept"
for fruit in "grape" "apple" "orange" "banana" "mango" "kiwi" "lemon"; do
    biglist.Add "$fruit" >/dev/null
done
count=$(biglist.count)
item0=$(biglist.Get 0)
item6=$(biglist.Get 6)
# Should be sorted: apple, banana, grape, kiwi, lemon, mango, orange
if [[ "$count" == "7" && "$item0" == "apple" && "$item6" == "orange" ]]; then
    kk_test_pass "Large sorted list maintained order"
else
    kk_test_fail "Count: $count, First: '$item0', Last: '$item6'"
fi
biglist.delete

# Cleanup
mylist.delete

kk_test_log "007_SortedListOperations.sh completed"
