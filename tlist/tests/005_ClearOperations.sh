#!/bin/bash
# 005_Clear_Operations.sh - Test Clear Operations
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tlist module
TLIST_DIR="$SCRIPT_DIR/.."
source "$TLIST_DIR/tlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "005: Clear Operations"

# Create TList instance
TList.new testlist

# Test: Clear empty list
kt_test_start "Clear empty list"
testlist.Clear
count=$(testlist.count)
capacity=$(testlist.capacity)
if [[ "$count" == "0" && "$capacity" == "0" ]]; then
    kt_test_pass "Clear empty list successful"
else
    kt_test_fail "Clear failed: count=$count, capacity=$capacity"
fi

# Test: Clear populated list
kt_test_start "Clear populated list"
# Add items and grow capacity
for i in {1..10}; do
    testlist.Add "item$i"
done
count_before=$(testlist.count)
capacity_before=$(testlist.capacity)
testlist.Clear
count_after=$(testlist.count)
capacity_after=$(testlist.capacity)
if [[ "$count_before" == "10" && "$count_after" == "0" && "$capacity_after" == "0" ]]; then
    kt_test_pass "Clear populated list successful: before(count=$count_before, cap=$capacity_before) after(count=$count_after, cap=$capacity_after)"
else
    kt_test_fail "Clear failed: before(count=$count_before, cap=$capacity_before) after(count=$count_after, cap=$capacity_after)"
fi

# Test: Verify items array is cleared
kt_test_start "Verify items array cleared"
declare -n items_ref="testlist_items"
if [[ ${#items_ref[@]} -eq 0 ]]; then
    kt_test_pass "Items array properly cleared"
else
    kt_test_fail "Items array not cleared: ${#items_ref[@]} elements remain"
fi

# Test: Operations after clear
kt_test_start "Operations after clear"
testlist.Add "new_item"
count=$(testlist.count)
declare -n items_ref2="testlist_items"
if [[ "$count" == "1" && "${items_ref2[0]}" == "new_item" ]]; then
    kt_test_pass "Operations work correctly after clear"
else
    kt_test_fail "Operations failed after clear: count=$count, item=${items_ref2[0]}"
fi

# Cleanup
testlist.delete

kt_test_log "005_Clear_Operations.sh completed"
