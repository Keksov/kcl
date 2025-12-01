#!/bin/bash
# 011_Move_Operations.sh - Test Move Operations
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

kt_test_section "011: Move Operations"

# Create TList instance and populate
TList.new testlist
testlist.Add "zero"
testlist.Add "one"
testlist.Add "two"
testlist.Add "three"

# Test: Move forward (from lower to higher index)
kt_test_start "Move forward"
testlist.Move 0 2
declare -n items_ref="testlist_items"
if [[ "${items_ref[0]}" == "one" && "${items_ref[1]}" == "two" && "${items_ref[2]}" == "zero" && "${items_ref[3]}" == "three" ]]; then
    kt_test_pass "Move 0->2 successful"
else
    kt_test_fail "Move failed: [0]=${items_ref[0]}, [1]=${items_ref[1]}, [2]=${items_ref[2]}, [3]=${items_ref[3]}"
fi

# Test: Move backward (from higher to lower index)
kt_test_start "Move backward"
testlist.Move 3 1
if [[ "${items_ref[0]}" == "one" && "${items_ref[1]}" == "three" && "${items_ref[2]}" == "two" && "${items_ref[3]}" == "zero" ]]; then
    kt_test_pass "Move 3->1 successful"
else
    kt_test_fail "Move failed: [0]=${items_ref[0]}, [1]=${items_ref[1]}, [2]=${items_ref[2]}, [3]=${items_ref[3]}"
fi

# Test: Move to same position (no-op)
kt_test_start "Move to same position"
original="${items_ref[2]}"
testlist.Move 2 2
if [[ "${items_ref[2]}" == "$original" ]]; then
    kt_test_pass "Move to same position had no effect"
else
    kt_test_fail "Move to same position changed data"
fi

# Test: Invalid from index (negative)
kt_test_start "Invalid from index - negative"
if testlist.Move -1 0 2>/dev/null; then
    kt_test_fail "Should have rejected negative from index"
else
    kt_test_pass "Correctly rejected negative from index"
fi

# Test: Invalid to index (out of bounds)
kt_test_start "Invalid to index - out of bounds"
if testlist.Move 0 10 2>/dev/null; then
    kt_test_fail "Should have rejected out of bounds to index"
else
    kt_test_pass "Correctly rejected out of bounds to index"
fi

# Cleanup
testlist.delete

kt_test_log "011_Move_Operations.sh completed"
