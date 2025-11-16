#!/bin/bash
# 015_performance_test.sh - Performance testing for TList operations

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "015"

test_section "015: Performance Testing"

# Test: Bulk add performance
test_start "Bulk add performance (1000 items)"
TList.new perflist
start_time=$(date +%s%N  || echo "0")
for i in {1..1000}; do
    perflist.Add "item$i"
done
end_time=$(date +%s%N  || echo "0")
count=$(perflist.count)
if [[ "$count" == "1000" ]]; then
    test_pass "Added 1000 items successfully"
else
    test_fail "Count after bulk add: $count (expected 1000)"
fi

# Test: Bulk insert performance (at beginning - worst case)
test_start "Bulk insert performance (100 inserts at start)"
start_time=$(date +%s%N  || echo "0")
for i in {1..100}; do
    perflist.Insert 0 "inserted$i"
done
end_time=$(date +%s%N  || echo "0")
count=$(perflist.count)
if [[ "$count" == "1100" ]]; then
    test_pass "Inserted 100 items at beginning successfully"
else
    test_fail "Count after bulk insert: $count (expected 1100)"
fi

# Test: Bulk delete performance (from end)
test_start "Bulk delete performance (remove 200 items)"
start_time=$(date +%s%N  || echo "0")
for i in {1..200}; do
    perflist.Delete $((count - 1))
    count=$((count - 1))
done
end_time=$(date +%s%N  || echo "0")
final_count=$(perflist.count)
if [[ "$final_count" == "900" ]]; then
    test_pass "Deleted 200 items from end successfully"
else
    test_fail "Count after bulk delete: $final_count (expected 900)"
fi

# Test: IndexOf performance on large list
test_start "IndexOf performance on large list"
target_item="item500"
start_time=$(date +%s%N  || echo "0")
perflist.IndexOf "$target_item"
index=$RESULT
end_time=$(date +%s%N  || echo "0")
if [[ "$index" -ge "100" ]]; then  # Should be at some position after inserts
    test_pass "IndexOf found item in large list"
else
    test_fail "IndexOf '$target_item' returned $index"
fi

# Test: Clear performance on large list
test_start "Clear performance on large list"
start_time=$(date +%s%N  || echo "0")
perflist.Clear
end_time=$(date +%s%N  || echo "0")
count=$(perflist.count)
capacity=$(perflist.capacity)
if [[ "$count" == "0" && "$capacity" == "0" ]]; then
    test_pass "Cleared large list successfully"
else
    test_fail "After clear: Count=$count, Capacity=$capacity"
fi

# Test: Capacity pre-allocation performance
test_start "Capacity pre-allocation performance"
perflist.capacity = "5000"
start_time=$(date +%s%N  || echo "0")
for i in {1..5000}; do
    perflist.Add "bulk$i"
done
end_time=$(date +%s%N  || echo "0")
count=$(perflist.count)
capacity=$(perflist.capacity)
if [[ "$count" == "5000" && "$capacity" -ge "5000" ]]; then
    test_pass "Bulk add with pre-allocated capacity successful"
else
    test_fail "Count=$count (expected 5000), Capacity=$capacity"
fi

# Cleanup
perflist.delete

test_info "015_performance_test.sh completed"
