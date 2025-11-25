#!/bin/bash
# 012_Pack_Operations.sh - Test Pack Operations
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

kk_test_section "012: Pack Operations"

# Create TList instance and populate with mixed content
TList.new testlist
testlist.Add "keep1"
testlist.Add ""
testlist.Add "keep2"
testlist.Add ""
testlist.Add ""

# Test: Pack removes empty strings
kk_test_start "Pack removes empty strings"
count_before=$(testlist.count)
testlist.Pack
count_after=$(testlist.count)
declare -n items_ref="testlist_items"
if [[ "$count_before" == "5" && "$count_after" == "2" && "${items_ref[0]}" == "keep1" && "${items_ref[1]}" == "keep2" ]]; then
    kk_test_pass "Pack removed empty strings: $count_before -> $count_after"
else
    kk_test_fail "Pack failed: before=$count_before, after=$count_after, items: [0]=${items_ref[0]}, [1]=${items_ref[1]}"
fi

# Test: Pack on list with no empties
kk_test_start "Pack on list with no empties"
testlist.Clear
testlist.Add "item1"
testlist.Add "item2"
count_before=$(testlist.count)
testlist.Pack
count_after=$(testlist.count)
if [[ "$count_before" == "$count_after" && "$count_after" == "2" ]]; then
    kk_test_pass "Pack on full list had no effect"
else
    kk_test_fail "Pack unexpectedly changed full list: $count_before -> $count_after"
fi

# Test: Pack on empty list
kk_test_start "Pack on empty list"
testlist.Clear
count_before=$(testlist.count)
testlist.Pack
count_after=$(testlist.count)
if [[ "$count_before" == "0" && "$count_after" == "0" ]]; then
    kk_test_pass "Pack on empty list had no effect"
else
    kk_test_fail "Pack on empty list changed count: $count_before -> $count_after"
fi

# Test: Pack with only empty strings
kk_test_start "Pack with only empty strings"
testlist.Add ""
testlist.Add ""
testlist.Add ""
count_before=$(testlist.count)
testlist.Pack
count_after=$(testlist.count)
if [[ "$count_before" == "3" && "$count_after" == "0" ]]; then
    kk_test_pass "Pack removed all empty strings"
else
    kk_test_fail "Pack failed on all-empty list: $count_before -> $count_after"
fi

# Cleanup
testlist.delete

kk_test_log "012_Pack_Operations.sh completed"
