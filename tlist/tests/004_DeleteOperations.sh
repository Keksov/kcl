#!/bin/bash
# 004_Delete_Operations.sh - Test Delete Operations
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

kt_test_section "004: Delete Operations"

# Create TList instance and populate
TList.new testlist
testlist.Add "item0"
testlist.Add "item1"
testlist.Add "item2"
testlist.Add "item3"

# Test: Delete from middle
kt_test_start "Delete from middle"
testlist.Delete 1
count=$(testlist.count)
declare -n items_ref="testlist_items"
if [[ "$count" == "3" && "${items_ref[0]}" == "item0" && "${items_ref[1]}" == "item2" && "${items_ref[2]}" == "item3" ]]; then
    kt_test_pass "Delete from middle successful"
else
    kt_test_fail "Delete failed: count=$count, items: [0]=${items_ref[0]}, [1]=${items_ref[1]}, [2]=${items_ref[2]}"
fi

# Test: Delete from beginning
kt_test_start "Delete from beginning"
testlist.Delete 0
count=$(testlist.count)
if [[ "$count" == "2" && "${items_ref[0]}" == "item2" && "${items_ref[1]}" == "item3" ]]; then
    kt_test_pass "Delete from beginning successful"
else
    kt_test_fail "Delete failed: count=$count, items: [0]=${items_ref[0]}, [1]=${items_ref[1]}"
fi

# Test: Delete from end
kt_test_start "Delete from end"
testlist.Delete 1
count=$(testlist.count)
if [[ "$count" == "1" && "${items_ref[0]}" == "item2" ]]; then
    kt_test_pass "Delete from end successful"
else
    kt_test_fail "Delete failed: count=$count, item=${items_ref[0]}"
fi

# Test: Delete last item
kt_test_start "Delete last item"
testlist.Delete 0
count=$(testlist.count)
if [[ "$count" == "0" ]]; then
    kt_test_pass "Delete last item successful"
else
    kt_test_fail "Delete failed: count=$count"
fi

# Test: Invalid index (negative)
kt_test_start "Invalid index - negative"
# Add items back
testlist.Add "test"
TRAP_ERRORS_ENABLED=false
testlist.Delete -1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kt_test_pass "Correctly rejected negative index"
else
    kt_test_fail "Should have rejected negative index"
fi

# Test: Invalid index (out of bounds)
kt_test_start "Invalid index - out of bounds"
TRAP_ERRORS_ENABLED=false
testlist.Delete 10
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kt_test_pass "Correctly rejected out of bounds index"
else
    kt_test_fail "Should have rejected out of bounds index"
fi

# Cleanup
testlist.delete

kt_test_log "004_Delete_Operations.sh completed"
