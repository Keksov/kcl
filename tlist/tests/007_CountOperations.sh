#!/bin/bash
# 007_Count_Operations.sh - Test Count Operations
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

kk_test_section "007: Count Operations"

# Create TList instance
TList.new testlist

# Test: Initial count
kk_test_start "Initial count"
count=$(testlist.count)
if [[ "$count" == "0" ]]; then
    kk_test_pass "Initial count is 0"
else
    kk_test_fail "Initial count is $count, expected 0"
fi

# Test: Count after Add
kk_test_start "Count after Add"
testlist.Add "item1"
count=$(testlist.count)
if [[ "$count" == "1" ]]; then
    kk_test_pass "Count correct after Add"
else
    kk_test_fail "Count incorrect after Add: $count"
fi

# Test: Count after Insert
kk_test_start "Count after Insert"
testlist.Insert 0 "inserted"
count=$(testlist.count)
if [[ "$count" == "2" ]]; then
    kk_test_pass "Count correct after Insert"
else
    kk_test_fail "Count incorrect after Insert: $count"
fi

# Test: Count after Delete
kk_test_start "Count after Delete"
testlist.Delete 1
count=$(testlist.count)
if [[ "$count" == "1" ]]; then
    kk_test_pass "Count correct after Delete"
else
    kk_test_fail "Count incorrect after Delete: $count"
fi

# Test: Count after Clear
kk_test_start "Count after Clear"
testlist.Clear
count=$(testlist.count)
if [[ "$count" == "0" ]]; then
    kk_test_pass "Count correct after Clear"
else
    kk_test_fail "Count incorrect after Clear: $count"
fi

# Test: Count consistency during multiple operations
kk_test_start "Count consistency during multiple operations"
for i in {1..10}; do
    testlist.Add "item$i"
done
count_add=$(testlist.count)
for i in {1..5}; do
    testlist.Delete 0
done
count_delete=$(testlist.count)
testlist.Insert 2 "inserted"
count_insert=$(testlist.count)
if [[ "$count_add" == "10" && "$count_delete" == "5" && "$count_insert" == "6" ]]; then
    kk_test_pass "Count remained consistent during operations"
else
    kk_test_fail "Count inconsistency: add=$count_add, delete=$count_delete, insert=$count_insert"
fi

# Cleanup
testlist.delete

kk_test_log "007_Count_Operations.sh completed"
