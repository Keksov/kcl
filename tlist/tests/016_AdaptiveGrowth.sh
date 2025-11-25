#!/bin/bash
# 016_Adaptive_Growth.sh - Test Adaptive Growth
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

kk_test_section "016: Adaptive Growth"

# Test: Small array growth (fixed to 4)
kk_test_start "Small array growth"
TList.new testlist
capacity_before=$(testlist.capacity)
testlist.Add "item1"
capacity_after=$(testlist.capacity)
if [[ "$capacity_before" == "0" && "$capacity_after" == "4" ]]; then
    kk_test_pass "Small array grew to fixed capacity 4"
else
    kk_test_fail "Small array growth failed: $capacity_before -> $capacity_after"
fi
testlist.delete

# Test: Medium array growth (2x multiplier)
kk_test_start "Medium array growth"
TList.new testlist
# Fill to capacity
for i in {1..8}; do
    testlist.Add "item$i"
done
capacity_before=$(testlist.capacity)
testlist.Add "trigger_growth"
capacity_after=$(testlist.capacity)
expected=$((capacity_before * 2))
if [[ "$capacity_after" == "$expected" ]]; then
    kk_test_pass "Medium array grew 2x: $capacity_before -> $capacity_after"
else
    kk_test_fail "Medium array growth failed: expected $expected, got $capacity_after"
fi
testlist.delete

# Test: Large array growth (1.5x multiplier)
kk_test_start "Large array growth"
TList.new testlist
# Fill to large size (>16)
for i in {1..16}; do
    testlist.Add "item$i"
done
capacity_before=$(testlist.capacity)
testlist.Add "trigger_large_growth"
capacity_after=$(testlist.capacity)
expected=$((capacity_before + capacity_before / 2))
if [[ "$capacity_after" == "$expected" ]]; then
    kk_test_pass "Large array grew 1.5x: $capacity_before -> $capacity_after"
else
    kk_test_fail "Large array growth failed: expected $expected, got $capacity_after"
fi
testlist.delete

# Test: Growth during Insert
kk_test_start "Growth during Insert"
TList.new testlist
testlist.Add "existing"
capacity_before=$(testlist.capacity)
testlist.Insert 1 "inserted"
capacity_after=$(testlist.capacity)
if [[ "$capacity_after" -ge "2" ]]; then
    kk_test_pass "Insert triggered appropriate growth: $capacity_before -> $capacity_after"
else
    kk_test_fail "Insert growth failed: $capacity_before -> $capacity_after"
fi
testlist.delete

# Test: No unnecessary growth
kk_test_start "No unnecessary growth"
TList.new testlist
testlist.Add "item1"
capacity_after_add=$(testlist.capacity)
testlist.Clear
capacity_after_clear=$(testlist.capacity)
if [[ "$capacity_after_clear" == "0" ]]; then
    kk_test_pass "Clear properly reset capacity"
else
    kk_test_fail "Clear did not reset capacity: $capacity_after_clear"
fi
testlist.delete

kk_test_log "016_Adaptive_Growth.sh completed"
