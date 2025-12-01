#!/bin/bash
# 015_Performance_Test.sh - Test Performance Test
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

kt_test_section "015: Performance Test"

# Test: Add performance
kt_test_start "Add performance - 1000 items"
TList.new testlist
start_time=$(date +%s%N)
for i in {1..1000}; do
    testlist.Add "item$i"
done
end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))  # milliseconds
count=$(testlist.count)
if [[ "$count" == "1000" ]]; then
    kt_test_pass "Added 1000 items in ${duration}ms"
else
    kt_test_fail "Add performance test failed: count=$count"
fi

# Test: Insert performance
kt_test_start "Insert performance - 100 inserts"
start_time=$(date +%s%N)
for i in {1..100}; do
    testlist.Insert $((i * 5)) "inserted$i"
done
end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))
count=$(testlist.count)
if [[ "$count" == "1100" ]]; then
    kt_test_pass "Inserted 100 items in ${duration}ms"
else
    kt_test_fail "Insert performance test failed: count=$count"
fi

# Test: IndexOf performance
kt_test_start "IndexOf performance - 100 searches"
start_time=$(date +%s%N)
for i in {1..100}; do
    testlist.IndexOf "item$((i * 5))"
done
end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))
kt_test_pass "Performed 100 IndexOf operations in ${duration}ms"

# Test: Delete performance
kt_test_start "Delete performance - 200 deletes"
start_time=$(date +%s%N)
for i in {1..200}; do
    testlist.Delete 0
done
end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))
count=$(testlist.count)
if [[ "$count" == "900" ]]; then
    kt_test_pass "Deleted 200 items in ${duration}ms"
else
    kt_test_fail "Delete performance test failed: count=$count"
fi

# Test: Large list operations
kt_test_start "Large list - 5000 items"
testlist.Clear
start_time=$(date +%s%N)
for i in {1..5000}; do
    testlist.Add "large$i"
done
end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))
count=$(testlist.count)
capacity=$(testlist.capacity)
if [[ "$count" == "5000" ]]; then
    kt_test_pass "Created large list (5000 items) in ${duration}ms, capacity=$capacity"
else
    kt_test_fail "Large list test failed: count=$count"
fi

# Test: Pack performance
kt_test_start "Pack performance - mixed content"
# Add many empty strings
for i in {1..1000}; do
    testlist.Add ""
done
count_before=$(testlist.count)
start_time=$(date +%s%N)
testlist.Pack
end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))
count_after=$(testlist.count)
if [[ "$count_before" == "6000" && "$count_after" == "5000" ]]; then
    kt_test_pass "Packed 6000->5000 items in ${duration}ms"
else
    kt_test_fail "Pack performance failed: $count_before -> $count_after"
fi

# Cleanup
testlist.delete

kt_test_log "015_Performance_Test.sh completed"
