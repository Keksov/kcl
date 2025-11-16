#!/bin/bash
# 017_BatchOperations.sh - Test batch insert and delete operations

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "017"

test_section "017: Batch Operations (BatchInsert and BatchDelete)"

# Test 1: BatchInsert at beginning
test_start "BatchInsert at beginning"
TList.new mylist1
mylist1.Add "a"
mylist1.Add "b"
mylist1.Add "c"
mylist1.BatchInsert 0 "x" "y"
declare -n items_ref1="mylist1_items"
if [[ "${items_ref1[0]}" == "x" && "${items_ref1[2]}" == "a" ]]; then
    test_pass "BatchInsert at beginning works correctly"
else
    test_fail "BatchInsert at beginning: expected x at [0] and a at [2], got ${items_ref1[0]} and ${items_ref1[2]}"
fi
mylist1.delete

# Test 2: BatchInsert in middle
test_start "BatchInsert in middle"
TList.new mylist2
mylist2.Add "a"
mylist2.Add "b"
mylist2.Add "c"
mylist2.BatchInsert 1 "x" "y"
declare -n items_ref2="mylist2_items"
if [[ "${items_ref2[1]}" == "x" && "${items_ref2[3]}" == "b" ]]; then
    test_pass "BatchInsert in middle works correctly"
else
    test_fail "BatchInsert in middle: expected x at [1] and b at [3], got ${items_ref2[1]} and ${items_ref2[3]}"
fi
mylist2.delete

# Test 3: BatchInsert at end
test_start "BatchInsert at end"
TList.new mylist3
mylist3.Add "a"
mylist3.Add "b"
mylist3.BatchInsert 2 "x" "y"
declare -n items_ref3="mylist3_items"
mylist3.Last
if [[ "${items_ref3[2]}" == "x" && "$RESULT" == "y" ]]; then
    test_pass "BatchInsert at end works correctly"
else
    test_fail "BatchInsert at end: expected x at [2] and y at last, got ${items_ref3[2]} and $RESULT"
fi
mylist3.delete

# Test 4: BatchInsert with capacity growth
test_start "BatchInsert with capacity growth"
TList.new mylist4
for (( i = 0; i < 5; i++ )); do
    mylist4.Add "item_$i" >/dev/null
done
declare -a new_items
for (( i = 0; i < 20; i++ )); do
    new_items+=("new_$i")
done
mylist4.BatchInsert 2 "${new_items[@]}"
count=$(mylist4.count)
if [[ "$count" == "25" ]]; then
    test_pass "BatchInsert with capacity growth: count is 25"
else
    test_fail "BatchInsert with capacity growth: count is $count, expected 25"
fi
mylist4.delete

# Test 5: BatchInsert with no items (no-op)
test_start "BatchInsert with no items (no-op)"
TList.new mylist5
mylist5.Add "a"
mylist5.Add "b"
mylist5.BatchInsert 0
if [[ "$RESULT" == "2" ]]; then
    test_pass "BatchInsert with no items returns current count"
else
    test_fail "BatchInsert with no items: expected 2, got $RESULT"
fi
mylist5.delete

# Test 6: BatchDelete from beginning
test_start "BatchDelete from beginning"
TList.new mylist6
for (( i = 0; i < 5; i++ )); do
    mylist6.Add "item_$i" >/dev/null
done
mylist6.BatchDelete 0 2
mylist6.First
if [[ "$RESULT" == "item_2" ]]; then
    test_pass "BatchDelete from beginning works correctly"
else
    test_fail "BatchDelete from beginning: expected first element to be item_2, got $RESULT"
fi
mylist6.delete

# Test 7: BatchDelete from middle
test_start "BatchDelete from middle"
TList.new mylist7
for (( i = 0; i < 5; i++ )); do
    mylist7.Add "item_$i" >/dev/null
done
mylist7.BatchDelete 1 2
declare -n items_ref7="mylist7_items"
if [[ "${items_ref7[1]}" == "item_3" ]]; then
    test_pass "BatchDelete from middle works correctly"
else
    test_fail "BatchDelete from middle: expected item_3 at [1], got ${items_ref7[1]}"
fi
mylist7.delete

# Test 8: BatchDelete from end
test_start "BatchDelete from end"
TList.new mylist8
for (( i = 0; i < 5; i++ )); do
    mylist8.Add "item_$i" >/dev/null
done
mylist8.BatchDelete 3 2
mylist8.Last
if [[ "$RESULT" == "item_2" ]]; then
    test_pass "BatchDelete from end works correctly"
else
    test_fail "BatchDelete from end: expected last element to be item_2, got $RESULT"
fi
mylist8.delete

# Test 9: BatchDelete with overflow (clamp)
test_start "BatchDelete with overflow (clamp)"
TList.new mylist9
for (( i = 0; i < 5; i++ )); do
    mylist9.Add "item_$i" >/dev/null
done
mylist9.BatchDelete 2 10
count=$(mylist9.count)
if [[ "$count" == "2" ]]; then
    test_pass "BatchDelete with overflow clamps correctly"
else
    test_fail "BatchDelete with overflow: count is $count, expected 2"
fi
mylist9.delete

# Test 10: BatchDelete with count=0 (no-op)
test_start "BatchDelete with count=0 (no-op)"
TList.new mylist10
mylist10.Add "a"
mylist10.Add "b"
mylist10.BatchDelete 0 0
count=$(mylist10.count)
if [[ "$count" == "2" ]]; then
    test_pass "BatchDelete with count=0 is no-op"
else
    test_fail "BatchDelete with count=0: count is $count, expected 2"
fi
mylist10.delete

# Test 11: BatchInsert out of bounds
test_start "BatchInsert out of bounds"
TList.new mylist11
mylist11.Add "a"
TRAP_ERRORS_ENABLED=false
mylist11.BatchInsert 5 "x"
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -eq 1 ]]; then
    test_pass "BatchInsert out of bounds returns error"
else
    test_fail "BatchInsert out of bounds should return error, got return code $result"
fi
mylist11.delete

# Test 12: BatchDelete out of bounds
test_start "BatchDelete out of bounds"
TList.new mylist12
mylist12.Add "a"
TRAP_ERRORS_ENABLED=false
mylist12.BatchDelete 5 1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -eq 1 ]]; then
    test_pass "BatchDelete out of bounds returns error"
else
    test_fail "BatchDelete out of bounds should return error, got return code $result"
fi
mylist12.delete

# Test 13: Alternating batch operations
test_start "Alternating batch operations"
TList.new mylist13
for (( i = 0; i < 3; i++ )); do
    mylist13.Add "a_$i" >/dev/null
done
mylist13.BatchInsert 1 "x" "y" >/dev/null
mylist13.BatchDelete 2 1 >/dev/null
mylist13.BatchInsert 3 "p" "q" >/dev/null
count=$(mylist13.count)
if [[ "$count" == "6" ]]; then
    test_pass "Alternating batch operations: count is 6"
else
    test_fail "Alternating batch operations: count is $count, expected 6"
fi
mylist13.delete

# Test 14: Integration with existing methods
test_start "Integration with existing methods"
TList.new mylist14
mylist14.Add "a"
mylist14.Add "b"
mylist14.BatchInsert 1 "x" "y" "z" >/dev/null
mylist14.Delete 2 >/dev/null
mylist14.Insert 0 "first" >/dev/null
count=$(mylist14.count)
if [[ "$count" == "5" ]]; then
    test_pass "Integration with existing methods: count is 5"
else
    test_fail "Integration with existing methods: count is $count, expected 5"
fi
mylist14.delete

test_info "017_BatchOperations.sh completed"
