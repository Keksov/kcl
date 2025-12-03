#!/bin/bash
# 003_Insert_Operations.sh - Test Insert Operations
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

kt_test_section "003: Insert Operations"

# Create TList instance
TList.new testlist

# Test: Insert at beginning
kt_test_start "Insert at beginning"
testlist.Insert 0 "first"
count=$(testlist.count)
declare -n items_ref="testlist_items"
if [[ "$count" == "1" && "${items_ref[0]}" == "first" ]]; then
    kt_test_pass "Insert at beginning successful"
else
    kt_test_fail "Insert failed: count=$count, item=${items_ref[0]}"
fi

# Test: Insert at end
kt_test_start "Insert at end"
testlist.Insert 1 "last"
count=$(testlist.count)
if [[ "$count" == "2" && "${items_ref[1]}" == "last" ]]; then
    kt_test_pass "Insert at end successful"
else
    kt_test_fail "Insert failed: count=$count, item=${items_ref[1]}"
fi

# Test: Insert in middle
kt_test_start "Insert in middle"
testlist.Insert 1 "middle"
count=$(testlist.count)
if [[ "$count" == "3" && "${items_ref[0]}" == "first" && "${items_ref[1]}" == "middle" && "${items_ref[2]}" == "last" ]]; then
    kt_test_pass "Insert in middle successful"
else
    kt_test_fail "Insert failed: count=$count, items: [0]=${items_ref[0]}, [1]=${items_ref[1]}, [2]=${items_ref[2]}"
fi

# Test: Insert with capacity growth
kt_test_start "Insert with capacity growth"
# Add more items to trigger growth (always insert at current count to add at end)
for i in {4..10}; do
    current_count=$(testlist.count)
    testlist.Insert $current_count "item$i"
done
count=$(testlist.count)
capacity=$(testlist.capacity)
if [[ "$count" == "10" && "$capacity" -ge "10" ]]; then
    kt_test_pass "Insert with growth successful: count=$count, capacity=$capacity"
else
    kt_test_fail "Growth failed: count=$count, capacity=$capacity"
fi

# Test: Invalid index (negative)
kt_test_start "Invalid index - negative"
testlist.Insert -1 "invalid" 2>&1 || exit_code=$?
if [[ ${exit_code:-0} -ne 0 ]]; then
    kt_test_pass "Correctly rejected negative index"
else
    kt_test_fail "Should have rejected negative index"
fi

# Test: Invalid index (too large)
kt_test_start "Invalid index - too large"
testlist.Insert 20 "invalid" 2>&1 || exit_code=$?
if [[ ${exit_code:-0} -ne 0 ]]; then
    kt_test_pass "Correctly rejected too large index"
else
    kt_test_fail "Should have rejected too large index"
fi

# Cleanup
testlist.delete

kt_test_log "003_Insert_Operations.sh completed"
