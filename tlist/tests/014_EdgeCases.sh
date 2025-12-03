#!/bin/bash
# 014_Edge_Cases.sh - Test Edge Cases
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

kt_test_section "014: Edge Cases"

# Test: Very large indices
kt_test_start "Very large indices"
TList.new testlist
testlist.Add "item"
TRAP_ERRORS_ENABLED=false
testlist.Insert 1000000 "large"
exit_code=$?
TRAP_ERRORS_ENABLED=true
if [[ $exit_code -ne 0 ]]; then
    kt_test_pass "Correctly rejected very large index"
else
    kt_test_fail "Should have rejected very large index"
fi
testlist.delete

# Test: Special characters in items
kt_test_start "Special characters in items"
TList.new testlist
testlist.Add "item with spaces"
testlist.Add 'item"with"quotes'
testlist.Add "item\nwith\nlines"
testlist.Add "item	with	tabs"
count=$(testlist.count)
if [[ "$count" == "4" ]]; then
    kt_test_pass "Special characters handled correctly"
else
    kt_test_fail "Special characters caused issues: count=$count"
fi
testlist.delete

# Test: Empty string operations
kt_test_start "Empty string operations"
TList.new testlist
testlist.Add ""
testlist.Insert 0 ""
testlist.Remove ""
count=$(testlist.count)
if [[ "$count" == "1" ]]; then
    kt_test_pass "Empty string operations work"
else
    kt_test_fail "Empty string operations failed: count=$count"
fi
testlist.delete

# Test: Rapid Add/Delete cycles
kt_test_start "Rapid Add/Delete cycles"
TList.new testlist
for i in {1..100}; do
    testlist.Add "item$i"
    testlist.Delete 0
done
count=$(testlist.count)
if [[ "$count" == "0" ]]; then
    kt_test_pass "Rapid cycles handled correctly"
else
    kt_test_fail "Rapid cycles left items: count=$count"
fi
testlist.delete

# Test: Boundary index operations
kt_test_start "Boundary index operations"
TList.new testlist
testlist.Add "only"
# Insert at count (append)
testlist.Insert 1 "appended"
# Delete at count-1 (last)
testlist.Delete 1
count=$(testlist.count)
declare -n items_ref="testlist_items"
if [[ "$count" == "1" && "${items_ref[0]}" == "only" ]]; then
    kt_test_pass "Boundary operations work"
else
    kt_test_fail "Boundary operations failed: count=$count, item=${items_ref[0]}"
fi
testlist.delete

# Test: Multiple instances isolation
kt_test_start "Multiple instances isolation"
TList.new list1
TList.new list2
list1.Add "list1_item"
list2.Add "list2_item"
count1=$(list1.count)
count2=$(list2.count)
declare -n items1_ref="list1_items"
declare -n items2_ref="list2_items"
if [[ "$count1" == "1" && "$count2" == "1" && "${items1_ref[0]}" == "list1_item" && "${items2_ref[0]}" == "list2_item" ]]; then
    kt_test_pass "Multiple instances isolated"
else
    kt_test_fail "Instances not isolated: l1=$count1(${items1_ref[0]}), l2=$count2(${items2_ref[0]})"
fi
list1.delete
list2.delete

# Test: Operations on deleted instance (should fail gracefully)
kt_test_start "Operations on deleted instance"
TList.new temp
temp.Add "test"
temp.delete
TRAP_ERRORS_ENABLED=false
temp.count >/dev/null 2>&1
exit_code=$?
TRAP_ERRORS_ENABLED=true
if [[ $exit_code -ne 0 ]]; then
    kt_test_pass "Operations on deleted instance fail gracefully"
else
    kt_test_fail "Operations on deleted instance should fail"
fi

# Integration Tests: Complex operation sequences
kt_test_start "Complex Add/Insert/Delete sequence"
TList.new complex
complex.Add "base1"
complex.Add "base2"
complex.Insert 1 "inserted"
complex.Add "base3"
complex.Delete 2
count=$(complex.count)
declare -n complex_ref="complex_items"
if [[ "$count" == "3" && "${complex_ref[0]}" == "base1" && "${complex_ref[1]}" == "inserted" && "${complex_ref[2]}" == "base3" ]]; then
    kt_test_pass "Complex sequence maintained correct state"
else
    kt_test_fail "Complex sequence failed: count=$count"
fi
complex.delete

kt_test_start "Search and modify integration"
TList.new searchtest
for i in {1..5}; do
    searchtest.Add "item$i"
done
searchtest.IndexOf "item3"
index="$RESULT"
if [[ "$index" == "2" ]]; then
    searchtest.Insert $index "before_item3"
    searchtest.Remove "item3"
    count=$(searchtest.count)
    declare -n search_ref="searchtest_items"
    if [[ "$count" == "5" && "${search_ref[2]}" == "before_item3" && "${search_ref[3]}" == "item4" ]]; then
        kt_test_pass "Search and modify integration successful"
    else
        kt_test_fail "Search and modify failed: count=$count"
    fi
else
    kt_test_fail "IndexOf failed to find item3"
fi
searchtest.delete

kt_test_start "Batch operations with search"
TList.new batchtest
batchtest.Add "marker"
batchtest.BatchInsert 1 "batch1" "batch2" "batch3"
batchtest.IndexOf "batch2"
index="$RESULT"
batchtest.BatchDelete $index 2
count=$(batchtest.count)
declare -n batch_ref="batchtest_items"
if [[ "$count" == "2" && "${batch_ref[0]}" == "marker" && "${batch_ref[1]}" == "batch1" ]]; then
    kt_test_pass "Batch operations with search successful"
else
    kt_test_fail "Batch operations with search failed: count=$count"
fi
batchtest.delete

kt_test_log "014_Edge_Cases.sh completed"
