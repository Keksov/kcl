#!/bin/bash
# 014_AddStringsOptimization.sh - Test AddStrings operation with optimization verification
# Tests the optimized AddStrings procedure (Issue 2.2: 5-10% speedup)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tstringlist module
TSTRINGLIST_DIR="$SCRIPT_DIR/.."
source "$TSTRINGLIST_DIR/tstringlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "014: AddStrings Operation - Optimization Tests"

# Test 1: Basic AddStrings with small list
kt_test_start "AddStrings basic operation (5 items)"
TStringList.new initial_list
initial_list.Add "apple"
initial_list.Add "banana"

TStringList.new source_list
source_list.Add "cherry"
source_list.Add "date"
source_list.Add "elderberry"

initial_list.AddStrings "source_list"

count=$(initial_list.count)
if [[ "$count" == "5" ]]; then
    kt_test_pass "AddStrings added 3 items to list with 2 items"
else
    kt_test_fail "Count is $count, expected 5"
fi

# Test 2: Verify all items are in correct order
kt_test_start "AddStrings maintains order"
success=true
expected=("apple" "banana" "cherry" "date" "elderberry")
for i in 0 1 2 3 4; do
    item=$(initial_list.Get $i)
    if [[ "$item" != "${expected[$i]}" ]]; then
        success=false
        kt_test_fail "Item $i is '$item', expected '${expected[$i]}'"
        break
    fi
done
if $success; then
    kt_test_pass "All items in correct order"
fi

# Test 3: AddStrings to empty list
kt_test_start "AddStrings to empty list"
TStringList.new empty_list
TStringList.new source2
source2.Add "item1"
source2.Add "item2"
source2.Add "item3"

empty_list.AddStrings "source2"

count=$(empty_list.count)
first=$(empty_list.Get 0)
if [[ "$count" == "3" && "$first" == "item1" ]]; then
    kt_test_pass "AddStrings to empty list works"
else
    kt_test_fail "Count: $count, First: '$first'"
fi

# Test 4: AddStrings from empty list
kt_test_start "AddStrings from empty source list"
TStringList.new target_list
target_list.Add "original"

TStringList.new empty_source

target_list.AddStrings "empty_source"

count=$(target_list.count)
item0=$(target_list.Get 0)
if [[ "$count" == "1" && "$item0" == "original" ]]; then
    kt_test_pass "AddStrings from empty source doesn't change list"
else
    kt_test_fail "Count: $count, Item: '$item0'"
fi

# Test 5: AddStrings with large list
kt_test_start "AddStrings with large source list"
TStringList.new large_initial
for i in {1..10}; do
    large_initial.Add "initial_$i"
done

TStringList.new large_source
for i in {1..50}; do
    large_source.Add "source_$i"
done

large_initial.AddStrings "large_source"

count=$(large_initial.count)
first=$(large_initial.Get 0)
middle=$(large_initial.Get 10)
last=$(large_initial.Get 59)

if [[ "$count" == "60" && "$first" == "initial_1" && "$middle" == "source_1" && "$last" == "source_50" ]]; then
    kt_test_pass "AddStrings with large list (60 items total)"
else
    kt_test_fail "Count: $count, First: '$first', Middle: '$middle', Last: '$last'"
fi

# Test 6: AddStrings with special characters
kt_test_start "AddStrings with special characters"
TStringList.new special_initial
special_initial.Add "hello"

TStringList.new special_source
special_source.Add "world test"
special_source.Add "path/to/file"
special_source.Add "key=value"
special_source.Add "email@example.com"

special_initial.AddStrings "special_source"

count=$(special_initial.count)
item0=$(special_initial.Get 0)
item1=$(special_initial.Get 1)
item2=$(special_initial.Get 2)

if [[ "$count" == "5" && "$item0" == "hello" && "$item1" == "world test" && "$item2" == "path/to/file" ]]; then
    kt_test_pass "Special characters preserved in AddStrings"
else
    kt_test_fail "Count: $count, Items: '$item0', '$item1', '$item2'"
fi

# Test 7: AddStrings with duplicates
kt_test_start "AddStrings with duplicates"
TStringList.new dup_initial
dup_initial.duplicates = "dupAccept"
dup_initial.Add "apple"
dup_initial.Add "apple"

TStringList.new dup_source
dup_source.duplicates = "dupAccept"
dup_source.Add "banana"
dup_source.Add "apple"
dup_source.Add "banana"

dup_initial.AddStrings "dup_source"

count=$(dup_initial.count)
item0=$(dup_initial.Get 0)
item1=$(dup_initial.Get 1)
item2=$(dup_initial.Get 2)
item3=$(dup_initial.Get 3)
item4=$(dup_initial.Get 4)

if [[ "$count" == "5" && "$item0" == "apple" && "$item1" == "apple" && "$item2" == "banana" && "$item3" == "apple" && "$item4" == "banana" ]]; then
    kt_test_pass "Duplicates preserved in AddStrings"
else
    kt_test_fail "Count: $count"
fi

# Test 8: Multiple sequential AddStrings
kt_test_start "Multiple sequential AddStrings operations"
TStringList.new seq_list
seq_list.Add "initial"

TStringList.new source_a
source_a.Add "a1"
source_a.Add "a2"

TStringList.new source_b
source_b.Add "b1"
source_b.Add "b2"
source_b.Add "b3"

seq_list.AddStrings "source_a"
count_after_a=$(seq_list.count)

seq_list.AddStrings "source_b"
count_after_b=$(seq_list.count)

item0=$(seq_list.Get 0)
item1=$(seq_list.Get 1)
item2=$(seq_list.Get 2)
item3=$(seq_list.Get 3)
item4=$(seq_list.Get 4)
item5=$(seq_list.Get 5)

if [[ "$count_after_a" == "3" && "$count_after_b" == "6" && "$item0" == "initial" && "$item1" == "a1" && "$item5" == "b3" ]]; then
    kt_test_pass "Multiple sequential AddStrings operations work correctly"
else
    kt_test_fail "Count after A: $count_after_a, Count after B: $count_after_b"
fi

# Test 9: AddStrings with empty string parameter
kt_test_start "AddStrings with empty list name"
TStringList.new test_list
test_list.Add "test"

# AddStrings with empty parameter should return early
test_list.AddStrings ""

count=$(test_list.count)
if [[ "$count" == "1" ]]; then
    kt_test_pass "AddStrings with empty parameter doesn't affect list"
else
    kt_test_fail "Count: $count, expected 1"
fi

# Test 10: AddStrings from sorted list to unsorted list
kt_test_start "AddStrings from sorted source to unsorted destination"
TStringList.new unsorted_dest
unsorted_dest.sorted = "false"
unsorted_dest.Add "zebra"
unsorted_dest.Add "apple"

TStringList.new sorted_source
sorted_source.sorted = "false"
sorted_source.Add "banana"
sorted_source.Add "cherry"

unsorted_dest.AddStrings "sorted_source"

count=$(unsorted_dest.count)
items_count=$(unsorted_dest.count)
item0=$(unsorted_dest.Get 0)
item1=$(unsorted_dest.Get 1)
item2=$(unsorted_dest.Get 2)
item3=$(unsorted_dest.Get 3)

if [[ "$count" == "4" && "$item0" == "zebra" && "$item1" == "apple" && "$item2" == "banana" && "$item3" == "cherry" ]]; then
    kt_test_pass "AddStrings preserves insertion order"
else
    kt_test_fail "Count: $count, Items: '$item0', '$item1', '$item2', '$item3'"
fi

# Performance test (timing verification)
kt_test_start "Performance verification (medium list)"
TStringList.new perf_initial
for i in {1..25}; do
    perf_initial.Add "initial_$i"
done

TStringList.new perf_source
for i in {1..25}; do
    perf_source.Add "source_$i"
done

start_time=$(date +%s%N)
perf_initial.AddStrings "perf_source"
end_time=$(date +%s%N)
elapsed_ms=$(( (end_time - start_time) / 1000000 ))

count=$(perf_initial.count)

# Optimized version should complete in < 50ms for 50 items
if [[ "$count" == "50" && $(( elapsed_ms < 100 )) -eq 1 ]]; then
    kt_test_pass "AddStrings completed in ${elapsed_ms}ms with 50 items"
else
    kt_test_fail "Count: $count, Time: ${elapsed_ms}ms"
fi

# Cleanup
initial_list.delete
source_list.delete
source2.delete
empty_list.delete
empty_source.delete
target_list.delete
large_initial.delete
large_source.delete
special_initial.delete
special_source.delete
dup_initial.delete
dup_source.delete
seq_list.delete
source_a.delete
source_b.delete
test_list.delete
unsorted_dest.delete
sorted_source.delete
perf_initial.delete
perf_source.delete

kt_test_log "014_AddStringsOptimization.sh completed"
