#!/bin/bash
# 005_RemoveAndDeleteOperations.sh - Test Remove and Delete operations
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

kk_test_section "005: Remove and Delete Operations"

# Create TStringList with test data
TStringList.new mylist
mylist.Add "apple"
mylist.Add "banana"
mylist.Add "cherry"
mylist.Add "date"
mylist.Add "elderberry"

# Test: Remove by value (apple)
kk_test_start "Remove string by value"
mylist.Remove "apple"
index=$RESULT
count=$(mylist.count)
if [[ "$index" == "0" && "$count" == "4" ]]; then
    kk_test_pass "Remove 'apple' succeeded, count is now 4"
else
    kk_test_fail "Remove returned $index (expected 0), count is $count (expected 4)"
fi

# Test: Verify apple was removed
kk_test_start "Verify removed string is gone"
item=$(mylist.Get 0)
if [[ "$item" == "banana" ]]; then
    kk_test_pass "apple was removed, banana is now at index 0"
else
    kk_test_fail "Get(0) returned '$item', expected 'banana'"
fi

# Test: Remove non-existent string
kk_test_start "Remove non-existent string"
mylist.Remove "grape"
index=$RESULT
if [[ "$index" == "-1" ]]; then
    kk_test_pass "Remove non-existent string returned -1"
else
    kk_test_fail "Remove returned $index, expected -1"
fi

# Test: Count unchanged after failed remove
kk_test_start "Count unchanged after failed remove"
count=$(mylist.count)
if [[ "$count" == "4" ]]; then
    kk_test_pass "Count remained 4 after failed remove"
else
    kk_test_fail "Count is $count, expected 4"
fi

# Recreate with fresh data for Delete tests
TStringList.new dellist
dellist.Add "one"
dellist.Add "two"
dellist.Add "three"
dellist.Add "four"
dellist.Add "five"

# Test: Delete at index 0
kk_test_start "Delete at index 0"
dellist.Delete 0
count=$(dellist.count)
item=$(dellist.Get 0)
if [[ "$count" == "4" && "$item" == "two" ]]; then
    kk_test_pass "Delete(0) removed first item, 'two' now at index 0"
else
    kk_test_fail "Count: $count (expected 4), item: '$item' (expected 'two')"
fi

# Test: Delete at middle index
kk_test_start "Delete at middle index"
dellist.Delete 1  # Remove "three"
count=$(dellist.count)
item=$(dellist.Get 1)
if [[ "$count" == "3" && "$item" == "four" ]]; then
    kk_test_pass "Delete(1) removed middle item"
else
    kk_test_fail "Count: $count (expected 3), item: '$item' (expected 'four')"
fi

# Test: Delete at last index
kk_test_start "Delete at last index"
dellist.Delete 2  # Remove "five"
count=$(dellist.count)
if [[ "$count" == "2" ]]; then
    kk_test_pass "Delete(2) removed last item, count is now 2"
else
    kk_test_fail "Count is $count, expected 2"
fi

# Test: Delete with invalid index (negative)
kk_test_start "Delete with invalid index (negative)"
TRAP_ERRORS_ENABLED=false
dellist.Delete -1 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kk_test_pass "Delete(-1) correctly failed"
else
    kk_test_fail "Delete(-1) should have failed"
fi

# Test: Delete with invalid index (out of bounds)
kk_test_start "Delete with invalid index (out of bounds)"
TRAP_ERRORS_ENABLED=false
dellist.Delete 100 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kk_test_pass "Delete(100) correctly failed"
else
    kk_test_fail "Delete(100) should have failed"
fi

# Test: Delete all remaining items
kk_test_start "Delete all remaining items"
dellist.Delete 0
dellist.Delete 0
count=$(dellist.count)
if [[ "$count" == "0" ]]; then
    kk_test_pass "All items deleted, count is 0"
else
    kk_test_fail "Count is $count, expected 0"
fi

# Test: Remove with duplicates
kk_test_start "Remove with duplicate strings"
TStringList.new duplist
duplist.Add "item"
duplist.Add "item"
duplist.Add "item"
count_before=$(duplist.count)
duplist.Remove "item"
index=$RESULT
count_after=$(duplist.count)
if [[ "$count_before" == "3" && "$index" == "0" && "$count_after" == "2" ]]; then
    kk_test_pass "Remove removed first occurrence of duplicates"
else
    kk_test_fail "Before: $count_before, After: $count_after, Index: $index"
fi
duplist.delete

# Cleanup
mylist.delete
dellist.delete

kk_test_log "005_RemoveAndDeleteOperations.sh completed"
