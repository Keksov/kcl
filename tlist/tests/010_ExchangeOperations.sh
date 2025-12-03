#!/bin/bash
# 010_Exchange_Operations.sh - Test Exchange Operations
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

kt_test_section "010: Exchange Operations"

# Create TList instance and populate
TList.new testlist
testlist.Add "first"
testlist.Add "second"
testlist.Add "third"

# Test: Exchange adjacent items
kt_test_start "Exchange adjacent items"
testlist.Exchange 0 1
declare -n items_ref="testlist_items"
if [[ "${items_ref[0]}" == "second" && "${items_ref[1]}" == "first" && "${items_ref[2]}" == "third" ]]; then
    kt_test_pass "Exchange 0<->1 successful"
else
    kt_test_fail "Exchange failed: [0]=${items_ref[0]}, [1]=${items_ref[1]}, [2]=${items_ref[2]}"
fi

# Test: Exchange non-adjacent items
kt_test_start "Exchange non-adjacent items"
testlist.Exchange 0 2
if [[ "${items_ref[0]}" == "third" && "${items_ref[1]}" == "first" && "${items_ref[2]}" == "second" ]]; then
    kt_test_pass "Exchange 0<->2 successful"
else
    kt_test_fail "Exchange failed: [0]=${items_ref[0]}, [1]=${items_ref[1]}, [2]=${items_ref[2]}"
fi

# Test: Exchange same index (no-op)
kt_test_start "Exchange same index"
original_first="${items_ref[0]}"
testlist.Exchange 1 1
if [[ "${items_ref[0]}" == "$original_first" ]]; then
    kt_test_pass "Exchange same index had no effect"
else
    kt_test_fail "Exchange same index changed data"
fi

# Test: Invalid index (negative)
kt_test_start "Invalid index - negative"
TRAP_ERRORS_ENABLED=false
testlist.Exchange -1 0 2>/dev/null
exit_code=$?
TRAP_ERRORS_ENABLED=true
if [[ $exit_code -ne 0 ]]; then
    kt_test_pass "Correctly rejected negative index"
else
    kt_test_fail "Should have rejected negative index"
fi

# Test: Invalid index (out of bounds)
kt_test_start "Invalid index - out of bounds"
TRAP_ERRORS_ENABLED=false
testlist.Exchange 0 10 2>/dev/null
exit_code=$?
TRAP_ERRORS_ENABLED=true
if [[ $exit_code -ne 0 ]]; then
    kt_test_pass "Correctly rejected out of bounds index"
else
    kt_test_fail "Should have rejected out of bounds index"
fi

# Cleanup
testlist.delete

kt_test_log "010_Exchange_Operations.sh completed"
