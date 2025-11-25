#!/bin/bash
# 006_Capacity_Operations.sh - Test Capacity Operations
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

kk_test_section "006: Capacity Operations"

# Create TList instance
TList.new testlist

# Test: Initial capacity
kk_test_start "Initial capacity"
capacity=$(testlist.capacity)
if [[ "$capacity" == "0" ]]; then
    kk_test_pass "Initial capacity is 0"
else
    kk_test_fail "Initial capacity is $capacity, expected 0"
fi

# Test: Capacity growth on Add
kk_test_start "Capacity growth on Add"
testlist.Add "item1"
capacity=$(testlist.capacity)
if [[ "$capacity" -ge "1" ]]; then
    kk_test_pass "Capacity grew to $capacity"
else
    kk_test_fail "Capacity did not grow: $capacity"
fi

# Test: Large capacity growth
kk_test_start "Large capacity growth"
for i in {2..20}; do
    testlist.Add "item$i"
done
count=$(testlist.count)
capacity=$(testlist.capacity)
if [[ "$count" == "20" && "$capacity" -ge "20" ]]; then
    kk_test_pass "Large growth successful: count=$count, capacity=$capacity"
else
    kk_test_fail "Large growth failed: count=$count, capacity=$capacity"
fi

# Test: Capacity reduction on Clear
kk_test_start "Capacity reduction on Clear"
testlist.Clear
count=$(testlist.count)
capacity=$(testlist.capacity)
if [[ "$count" == "0" && "$capacity" == "0" ]]; then
    kk_test_pass "Capacity reduced to 0 on Clear"
else
    kk_test_fail "Capacity not reduced: count=$count, capacity=$capacity"
fi

# Test: Capacity management with Insert
kk_test_start "Capacity with Insert"
testlist.Add "base"
testlist.Insert 0 "inserted"
count=$(testlist.count)
capacity=$(testlist.capacity)
if [[ "$count" == "2" && "$capacity" -ge "2" ]]; then
    kk_test_pass "Insert managed capacity: count=$count, capacity=$capacity"
else
    kk_test_fail "Insert capacity issue: count=$count, capacity=$capacity"
fi

# Test: Capacity behavior with Delete
kk_test_start "Capacity with Delete"
testlist.Delete 0
count=$(testlist.count)
capacity=$(testlist.capacity)
if [[ "$count" == "1" ]]; then
    kk_test_pass "Delete maintained capacity appropriately: count=$count, capacity=$capacity"
else
    kk_test_fail "Delete issue: count=$count, capacity=$capacity"
fi

# Cleanup
testlist.delete

kk_test_log "006_Capacity_Operations.sh completed"
