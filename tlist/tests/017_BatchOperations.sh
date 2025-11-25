#!/bin/bash
# 017_Batch_Operations.sh - Test Batch Operations
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

kk_test_section "017: Batch Operations"

# Create TList instance and populate
TList.new testlist
testlist.Add "base1"
testlist.Add "base2"

# Test: BatchInsert multiple items
kk_test_start "BatchInsert multiple items"
count_before=$(testlist.count)
testlist.BatchInsert 1 "inserted1" "inserted2" "inserted3"
count_after=$(testlist.count)
declare -n items_ref="testlist_items"
if [[ "$count_before" == "2" && "$count_after" == "5" && "${items_ref[0]}" == "base1" && "${items_ref[1]}" == "inserted1" && "${items_ref[2]}" == "inserted2" && "${items_ref[3]}" == "inserted3" && "${items_ref[4]}" == "base2" ]]; then
    kk_test_pass "BatchInsert successful: inserted 3 items at index 1"
else
    kk_test_fail "BatchInsert failed: before=$count_before, after=$count_after"
fi

# Test: BatchInsert at beginning
kk_test_start "BatchInsert at beginning"
testlist.BatchInsert 0 "start1" "start2"
count=$(testlist.count)
if [[ "$count" == "7" && "${items_ref[0]}" == "start1" && "${items_ref[1]}" == "start2" ]]; then
    kk_test_pass "BatchInsert at beginning successful"
else
    kk_test_fail "BatchInsert at beginning failed: count=$count"
fi

# Test: BatchInsert at end
kk_test_start "BatchInsert at end"
testlist.BatchInsert 7 "end1" "end2"
count=$(testlist.count)
if [[ "$count" == "9" && "${items_ref[7]}" == "end1" && "${items_ref[8]}" == "end2" ]]; then
    kk_test_pass "BatchInsert at end successful"
else
    kk_test_fail "BatchInsert at end failed: count=$count"
fi

# Test: BatchDelete multiple items
kk_test_start "BatchDelete multiple items"
count_before=$(testlist.count)
testlist.BatchDelete 2 3  # Delete 3 items starting at index 2
count_after=$(testlist.count)
if [[ "$count_before" == "9" && "$count_after" == "6" ]]; then
    kk_test_pass "BatchDelete successful: removed 3 items"
else
    kk_test_fail "BatchDelete failed: $count_before -> $count_after"
fi

# Test: BatchDelete from end
kk_test_start "BatchDelete from end"
testlist.BatchDelete 4 2  # Delete last 2 items
count=$(testlist.count)
if [[ "$count" == "4" ]]; then
    kk_test_pass "BatchDelete from end successful"
else
    kk_test_fail "BatchDelete from end failed: count=$count"
fi

# Test: BatchInsert empty
kk_test_start "BatchInsert empty"
count_before=$(testlist.count)
testlist.BatchInsert 2
count_after=$(testlist.count)
if [[ "$count_before" == "$count_after" ]]; then
    kk_test_pass "BatchInsert empty had no effect"
else
    kk_test_fail "BatchInsert empty changed count: $count_before -> $count_after"
fi

# Test: BatchDelete zero items
kk_test_start "BatchDelete zero items"
count_before=$(testlist.count)
testlist.BatchDelete 1 0
count_after=$(testlist.count)
if [[ "$count_before" == "$count_after" ]]; then
    kk_test_pass "BatchDelete zero items had no effect"
else
    kk_test_fail "BatchDelete zero items changed count: $count_before -> $count_after"
fi

# Test: Invalid BatchInsert index
kk_test_start "Invalid BatchInsert index"
result=$(testlist.BatchInsert -1 "invalid" 2>&1)
exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    kk_test_pass "BatchInsert rejected invalid index"
else
    kk_test_fail "BatchInsert should reject invalid index"
fi

# Cleanup
testlist.delete

kk_test_log "017_Batch_Operations.sh completed"
