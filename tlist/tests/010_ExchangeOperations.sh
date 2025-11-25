#!/bin/bash
# 010_Exchange_Operations.sh - Test Exchange Operations
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

kk_test_section "010: Exchange Operations"

# Create TList instance and populate
TList.new testlist
testlist.Add "first"
testlist.Add "second"
testlist.Add "third"

# Test: Exchange adjacent items
kk_test_start "Exchange adjacent items"
testlist.Exchange 0 1
declare -n items_ref="testlist_items"
if [[ "${items_ref[0]}" == "second" && "${items_ref[1]}" == "first" && "${items_ref[2]}" == "third" ]]; then
    kk_test_pass "Exchange 0<->1 successful"
else
    kk_test_fail "Exchange failed: [0]=${items_ref[0]}, [1]=${items_ref[1]}, [2]=${items_ref[2]}"
fi

# Test: Exchange non-adjacent items
kk_test_start "Exchange non-adjacent items"
testlist.Exchange 0 2
if [[ "${items_ref[0]}" == "third" && "${items_ref[1]}" == "first" && "${items_ref[2]}" == "second" ]]; then
    kk_test_pass "Exchange 0<->2 successful"
else
    kk_test_fail "Exchange failed: [0]=${items_ref[0]}, [1]=${items_ref[1]}, [2]=${items_ref[2]}"
fi

# Test: Exchange same index (no-op)
kk_test_start "Exchange same index"
original_first="${items_ref[0]}"
testlist.Exchange 1 1
if [[ "${items_ref[0]}" == "$original_first" ]]; then
    kk_test_pass "Exchange same index had no effect"
else
    kk_test_fail "Exchange same index changed data"
fi

# Test: Invalid index (negative)
kk_test_start "Invalid index - negative"
result=$(testlist.Exchange -1 0 2>&1)
exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    kk_test_pass "Correctly rejected negative index"
else
    kk_test_fail "Should have rejected negative index"
fi

# Test: Invalid index (out of bounds)
kk_test_start "Invalid index - out of bounds"
result=$(testlist.Exchange 0 10 2>&1)
exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    kk_test_pass "Correctly rejected out of bounds index"
else
    kk_test_fail "Should have rejected out of bounds index"
fi

# Cleanup
testlist.delete

kk_test_log "010_Exchange_Operations.sh completed"
