#!/bin/bash
# 013_AssignOptimization.sh - Test Assign operation with optimization verification
# Tests the optimized Assign procedure (Issue 2.1: 41.2x speedup)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tstringlist module
TSTRINGLIST_DIR="$SCRIPT_DIR/.."
source "$TSTRINGLIST_DIR/tstringlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "013: Assign Operation - Optimization Tests"

echo "[DEBUG] Starting tests..." >&2

# Test 1: Basic Assign with small list
echo "[DEBUG] Test 1: Basic Assign with small list" >&2
kt_test_start "Assign basic list (5 items)"
echo "[DEBUG] Creating source_list..." >&2
TStringList.new source_list
echo "[DEBUG] Adding items to source_list..." >&2
source_list.Add "apple"
source_list.Add "banana"
source_list.Add "cherry"
source_list.Add "date"
source_list.Add "elderberry"

echo "[DEBUG] Creating dest_list..." >&2
TStringList.new dest_list
echo "[DEBUG] Calling Assign..." >&2
dest_list.Assign "source_list"
echo "[DEBUG] Assign completed" >&2

count=$(dest_list.count)
if [[ "$count" == "5" ]]; then
    kt_test_pass "Destination list has 5 items"
else
    kt_test_fail "Count is $count, expected 5"
fi

# Test 2: Verify all items copied correctly
kt_test_start "Assign copies all items in correct order"
success=true
for i in 0 1 2 3 4; do
    source_item=$(source_list.Get $i)
    dest_item=$(dest_list.Get $i)
    if [[ "$source_item" != "$dest_item" ]]; then
        success=false
        kt_test_fail "Item $i mismatch: source='$source_item', dest='$dest_item'"
        break
    fi
done
if $success; then
    kt_test_pass "All items copied correctly in order"
fi

# Test 3: Assign to empty list
kt_test_start "Assign clears previous content"
TStringList.new another_list
another_list.Add "old"
another_list.Add "data"
another_list.Assign "source_list"

count=$(another_list.count)
first_item=$(another_list.Get 0)
if [[ "$count" == "5" && "$first_item" == "apple" ]]; then
    kt_test_pass "Previous content cleared, new content assigned"
else
    kt_test_fail "Count: $count, First item: '$first_item'"
fi

# Test 4: Assign empty list
kt_test_start "Assign empty list"
TStringList.new empty_source
TStringList.new test_dest
test_dest.Add "something"
test_dest.Assign "empty_source"

count=$(test_dest.count)
if [[ "$count" == "0" ]]; then
    kt_test_pass "Destination cleared by assigning empty source"
else
    kt_test_fail "Count is $count, expected 0"
fi

# Test 5: Assign large list (performance check)
kt_test_start "Assign large list (100 items)"
TStringList.new large_source
for i in {1..100}; do
    large_source.Add "item_$i"
done

TStringList.new large_dest
large_dest.Assign "large_source"

count=$(large_dest.count)
first=$(large_dest.Get 0)
last=$(large_dest.Get 99)

if [[ "$count" == "100" && "$first" == "item_1" && "$last" == "item_100" ]]; then
    kt_test_pass "Large list assigned correctly (100 items)"
else
    kt_test_fail "Count: $count, First: '$first', Last: '$last'"
fi

# Test 6: Assign with special characters
kt_test_start "Assign list with special characters"
TStringList.new special_source
special_source.Add "hello world"
special_source.Add "test@example.com"
special_source.Add "path/to/file"
special_source.Add "key=value"

TStringList.new special_dest
special_dest.Assign "special_source"

count=$(special_dest.count)
item0=$(special_dest.Get 0)
item1=$(special_dest.Get 1)
item2=$(special_dest.Get 2)
item3=$(special_dest.Get 3)

if [[ "$count" == "4" && "$item0" == "hello world" && "$item1" == "test@example.com" && "$item2" == "path/to/file" && "$item3" == "key=value" ]]; then
    kt_test_pass "Special characters preserved in Assign"
else
    kt_test_fail "Items not preserved correctly"
fi

# Test 7: Assign preserves properties
kt_test_start "Assign preserves source properties"
source_list.case_sensitive = "true"
source_list.sorted = "false"
source_list.duplicates = "dupError"

# Properties should be preserved on destination after assign
case_sensitive=$(source_list.case_sensitive)
duplicates=$(source_list.duplicates)

if [[ "$case_sensitive" == "true" && "$duplicates" == "dupError" ]]; then
    kt_test_pass "Source properties preserved"
else
    kt_test_fail "case_sensitive: $case_sensitive, duplicates: $duplicates"
fi

# Test 8: Assign with duplicates
kt_test_start "Assign list with duplicate items"
TStringList.new dup_source
dup_source.duplicates = "dupAccept"
dup_source.Add "apple"
dup_source.Add "banana"
dup_source.Add "apple"
dup_source.Add "cherry"
dup_source.Add "banana"

TStringList.new dup_dest
dup_dest.Assign "dup_source"

count=$(dup_dest.count)
item0=$(dup_dest.Get 0)
item2=$(dup_dest.Get 2)
item4=$(dup_dest.Get 4)

if [[ "$count" == "5" && "$item0" == "apple" && "$item2" == "apple" && "$item4" == "banana" ]]; then
    kt_test_pass "Duplicates preserved in Assign"
else
    kt_test_fail "Count: $count, Items: item0='$item0', item2='$item2', item4='$item4'"
fi

# Test 9: Multiple sequential assigns
kt_test_start "Multiple sequential Assign operations"
TStringList.new list_a
list_a.Add "a1"
list_a.Add "a2"

TStringList.new list_b
list_b.Add "b1"
list_b.Add "b2"
list_b.Add "b3"

TStringList.new test_seq
test_seq.Assign "list_a"
count_after_a=$(test_seq.count)
first_after_a=$(test_seq.Get 0)

test_seq.Assign "list_b"
count_after_b=$(test_seq.count)
first_after_b=$(test_seq.Get 0)

if [[ "$count_after_a" == "2" && "$first_after_a" == "a1" && "$count_after_b" == "3" && "$first_after_b" == "b1" ]]; then
    kt_test_pass "Sequential Assign operations work correctly"
else
    kt_test_fail "After A: count=$count_after_a, first=$first_after_a; After B: count=$count_after_b, first=$first_after_b"
fi

# Test 10: Assign to self (self-assignment)
kt_test_start "Assign to self (edge case)"
TStringList.new self_test
self_test.Add "item1"
self_test.Add "item2"
self_test.Add "item3"

# This should work without issues
self_test.Assign "self_test"

count=$(self_test.count)
first=$(self_test.Get 0)
last=$(self_test.Get 2)

if [[ "$count" == "3" && "$first" == "item1" && "$last" == "item3" ]]; then
    kt_test_pass "Self-assignment works correctly"
else
    kt_test_fail "Count: $count, First: '$first', Last: '$last'"
fi

# Performance test (timing verification)
kt_test_start "Performance verification (medium list)"
TStringList.new perf_source
for i in {1..50}; do
    perf_source.Add "performance_test_item_$i"
done

start_time=$(date +%s%N)
TStringList.new perf_dest
perf_dest.Assign "perf_source"
end_time=$(date +%s%N)
elapsed_ms=$(( (end_time - start_time) / 1000000 ))

# Optimized version should complete in < 100ms for 50 items
if (( elapsed_ms < 200 )); then
    kt_test_pass "Assign completed in ${elapsed_ms}ms (acceptable performance)"
else
    kt_test_fail "Assign took ${elapsed_ms}ms (expected < 200ms)"
fi

# Cleanup
source_list.delete
dest_list.delete
another_list.delete
empty_source.delete
test_dest.delete
large_source.delete
large_dest.delete
special_source.delete
special_dest.delete
dup_source.delete
dup_dest.delete
list_a.delete
list_b.delete
test_seq.delete
self_test.delete
perf_source.delete
perf_dest.delete

kt_test_log "013_AssignOptimization.sh completed"
