#!/bin/bash
# 009_Remove_Operations.sh - Test Remove Operations
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

kt_test_section "009: Remove Operations"

# Create TList instance and populate
TList.new testlist
testlist.Add "apple"
testlist.Add "banana"
testlist.Add "apple"
testlist.Add "cherry"

# Test: Remove existing item (first occurrence)
kt_test_start "Remove existing item"
testlist.Remove "apple"
count=$(testlist.count)
declare -n items_ref="testlist_items"
if [[ "$count" == "3" && "${items_ref[0]}" == "banana" && "${items_ref[1]}" == "apple" && "${items_ref[2]}" == "cherry" ]]; then
    kt_test_pass "Remove first apple successful"
else
    kt_test_fail "Remove failed: count=$count, items: [0]=${items_ref[0]}, [1]=${items_ref[1]}, [2]=${items_ref[2]}"
fi

# Test: Remove middle item
kt_test_start "Remove middle item"
testlist.Remove "apple"
count=$(testlist.count)
if [[ "$count" == "2" && "${items_ref[0]}" == "banana" && "${items_ref[1]}" == "cherry" ]]; then
    kt_test_pass "Remove second apple successful"
else
    kt_test_fail "Remove failed: count=$count, items: [0]=${items_ref[0]}, [1]=${items_ref[1]}"
fi

# Test: Remove non-existing item
kt_test_start "Remove non-existing item"
testlist.Remove "grape"
count=$(testlist.count)
if [[ "$count" == "2" ]]; then
    kt_test_pass "Remove non-existing item had no effect"
else
    kt_test_fail "Remove non-existing changed count: $count"
fi

# Test: Remove from empty list
kt_test_start "Remove from empty list"
TList.new emptylist
emptylist.Remove "anything"
count=$(emptylist.count)
if [[ "$count" == "0" ]]; then
    kt_test_pass "Remove from empty list had no effect"
else
    kt_test_fail "Remove from empty list changed count: $count"
fi
emptylist.delete

# Test: Remove empty string
kt_test_start "Remove empty string"
testlist.Add ""
testlist.Remove ""
count=$(testlist.count)
if [[ "$count" == "2" ]]; then
    kt_test_pass "Remove empty string successful"
else
    kt_test_fail "Remove empty string failed: count=$count"
fi

# Cleanup
testlist.delete

kt_test_log "009_Remove_Operations.sh completed"
