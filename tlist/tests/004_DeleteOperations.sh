#!/bin/bash
# 004_Delete_Operations.sh - Test Delete Operations
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tlist module
TLIST_DIR="$SCRIPT_DIR/.."
source "$TLIST_DIR/tlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kk_test_section "004: Delete Operations"

# Create TList instance and populate
TList.new testlist
testlist.Add "item0"
testlist.Add "item1"
testlist.Add "item2"
testlist.Add "item3"

# Test: Delete from middle
kk_test_start "Delete from middle"
testlist.Delete 1
count=$(testlist.count)
declare -n items_ref="testlist_items"
if [[ "$count" == "3" && "${items_ref[0]}" == "item0" && "${items_ref[1]}" == "item2" && "${items_ref[2]}" == "item3" ]]; then
    kk_test_pass "Delete from middle successful"
else
    kk_test_fail "Delete failed: count=$count, items: [0]=${items_ref[0]}, [1]=${items_ref[1]}, [2]=${items_ref[2]}"
fi

# Test: Delete from beginning
kk_test_start "Delete from beginning"
testlist.Delete 0
count=$(testlist.count)
if [[ "$count" == "2" && "${items_ref[0]}" == "item2" && "${items_ref[1]}" == "item3" ]]; then
    kk_test_pass "Delete from beginning successful"
else
    kk_test_fail "Delete failed: count=$count, items: [0]=${items_ref[0]}, [1]=${items_ref[1]}"
fi

# Test: Delete from end
kk_test_start "Delete from end"
testlist.Delete 1
count=$(testlist.count)
if [[ "$count" == "1" && "${items_ref[0]}" == "item2" ]]; then
    kk_test_pass "Delete from end successful"
else
    kk_test_fail "Delete failed: count=$count, item=${items_ref[0]}"
fi

# Test: Delete last item
kk_test_start "Delete last item"
testlist.Delete 0
count=$(testlist.count)
if [[ "$count" == "0" ]]; then
    kk_test_pass "Delete last item successful"
else
    kk_test_fail "Delete failed: count=$count"
fi

# Test: Invalid index (negative)
kk_test_start "Invalid index - negative"
# Add items back
testlist.Add "test"
result=$(testlist.Delete -1 2>&1)
exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    kk_test_pass "Correctly rejected negative index"
else
    kk_test_fail "Should have rejected negative index"
fi

# Test: Invalid index (out of bounds)
kk_test_start "Invalid index - out of bounds"
result=$(testlist.Delete 10 2>&1)
exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    kk_test_pass "Correctly rejected out of bounds index"
else
    kk_test_fail "Should have rejected out of bounds index"
fi

# Cleanup
testlist.delete

kk_test_log "004_Delete_Operations.sh completed"
