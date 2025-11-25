#!/bin/bash
# 008_ClearAndCopyOperations.sh - Test Clear and Copy operations
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

kk_test_section "008: Clear and Copy Operations"

# Create a list with data
TStringList.new mylist
mylist.Add "apple" >/dev/null
mylist.Add "banana" >/dev/null
mylist.Add "cherry" >/dev/null
mylist.Add "date" >/dev/null
mylist.Add "elderberry" >/dev/null

# Test: Count before clear
kk_test_start "Verify list has data before clear"
count=$(mylist.count)
if [[ "$count" == "5" ]]; then
    kk_test_pass "List has 5 items before clear"
else
    kk_test_fail "Count is $count, expected 5"
fi

# Test: Clear the list
kk_test_start "Clear the list"
mylist.Clear
count=$(mylist.count)
if [[ "$count" == "0" ]]; then
    kk_test_pass "List cleared successfully, count is 0"
else
    kk_test_fail "Count is $count, expected 0"
fi

# Test: Capacity after clear
kk_test_start "Capacity after clear"
capacity=$(mylist.capacity)
if [[ "$capacity" == "0" ]]; then
    kk_test_pass "Capacity is 0 after clear"
else
    kk_test_fail "Capacity is $capacity, expected 0"
fi

# Test: Can add to cleared list
kk_test_start "Add to cleared list"
mylist.Add "fig" >/dev/null
count=$(mylist.count)
item=$(mylist.Get 0)
if [[ "$count" == "1" && "$item" == "fig" ]]; then
    kk_test_pass "Successfully added to cleared list"
else
    kk_test_fail "Count: $count (expected 1), Item: '$item'"
fi

# Test: Clear empty list (should not error)
kk_test_start "Clear empty list"
mylist.Clear
count=$(mylist.count)
if [[ "$count" == "0" ]]; then
    kk_test_pass "Clear on empty list succeeded"
else
    kk_test_fail "Count is $count, expected 0"
fi

# Test: Clear respects other properties
kk_test_start "Properties preserved after clear"
mylist.case_sensitive = "true"
mylist.duplicates = "dupError"
mylist.Clear
case_sensitive=$(mylist.case_sensitive)
if [[ "$case_sensitive" == "true" ]]; then
    kk_test_pass "Properties preserved after clear"
else
    kk_test_fail "Properties not preserved"
fi

# Test: Clear large list
kk_test_start "Clear large list"
TStringList.new largelist
for i in {1..100}; do
    largelist.Add "item$i" >/dev/null
done
count_before=$(largelist.count)
largelist.Clear
count_after=$(largelist.count)
if [[ "$count_before" == "100" && "$count_after" == "0" ]]; then
    kk_test_pass "Large list cleared successfully"
else
    kk_test_fail "Before: $count_before, After: $count_after"
fi
largelist.delete

# Cleanup
mylist.delete

kk_test_log "008_ClearAndCopyOperations.sh completed"
