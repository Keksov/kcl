#!/bin/bash

# Source the TList implementation
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tlist.sh"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test helper
test_result() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        ((TESTS_FAILED++)) || true
    fi
}

echo "=== TList Batch Operations Test Suite ==="
echo ""

# Test 1: BatchInsert at beginning
echo "Test 1: BatchInsert at beginning"
TList.new mylist1
mylist1.Add "a"
mylist1.Add "b"
mylist1.Add "c"
mylist1.BatchInsert 0 "x" "y"
declare -n items_ref1="mylist1_items"
test_result "First element is 'x'" "x" "${items_ref1[0]}"
test_result "Element at index 2 is 'a'" "a" "${items_ref1[2]}"
echo ""

# Test 2: BatchInsert in middle
echo "Test 2: BatchInsert in middle"
TList.new mylist2
mylist2.Add "a"
mylist2.Add "b"
mylist2.Add "c"
mylist2.BatchInsert 1 "x" "y"
declare -n items_ref2="mylist2_items"
test_result "Element at index 1 is 'x'" "x" "${items_ref2[1]}"
test_result "Element at index 3 is 'b'" "b" "${items_ref2[3]}"
echo ""

# Test 3: BatchInsert at end
echo "Test 3: BatchInsert at end"
TList.new mylist3
mylist3.Add "a"
mylist3.Add "b"
mylist3.BatchInsert 2 "x" "y"
declare -n items_ref3="mylist3_items"
test_result "Element at index 2 is 'x'" "x" "${items_ref3[2]}"
mylist3.Last
test_result "Last element is 'y'" "y" "$RESULT"
echo ""

# Test 4: BatchInsert with capacity growth
echo "Test 4: BatchInsert with capacity growth"
TList.new mylist4
for (( i = 0; i < 5; i++ )); do
    mylist4.Add "item_$i"
done
# Add 20 items to force capacity growth
declare -a new_items
for (( i = 0; i < 20; i++ )); do
    new_items+=("new_$i")
done
mylist4.BatchInsert 2 "${new_items[@]}"
count=$(mylist4.count)
test_result "Count is 25 after BatchInsert" "25" "$count"
echo ""

# Test 5: BatchInsert with no items (no-op)
echo "Test 5: BatchInsert with no items (no-op)"
TList.new mylist5
mylist5.Add "a"
mylist5.Add "b"
mylist5.BatchInsert 0
test_result "Count remains 2 after empty BatchInsert" "2" "$RESULT"
echo ""

# Test 6: BatchDelete from beginning
echo "Test 6: BatchDelete from beginning"
TList.new mylist6
for (( i = 0; i < 5; i++ )); do
    mylist6.Add "item_$i"
done
mylist6.BatchDelete 0 2
test_result "Count is 3 after BatchDelete 2 from beginning" "3" "$RESULT"
mylist6.First
test_result "First element is 'item_2'" "item_2" "$RESULT"
echo ""

# Test 7: BatchDelete from middle
echo "Test 7: BatchDelete from middle"
TList.new mylist7
for (( i = 0; i < 5; i++ )); do
    mylist7.Add "item_$i"
done
mylist7.BatchDelete 1 2
test_result "Count is 3 after BatchDelete 2 from middle" "3" "$RESULT"
declare -n items_ref7="mylist7_items"
test_result "Element at index 1 is 'item_3'" "item_3" "${items_ref7[1]}"
echo ""

# Test 8: BatchDelete from end
echo "Test 8: BatchDelete from end"
TList.new mylist8
for (( i = 0; i < 5; i++ )); do
    mylist8.Add "item_$i"
done
mylist8.BatchDelete 3 2
test_result "Count is 3 after BatchDelete 2 from end" "3" "$RESULT"
mylist8.Last
test_result "Last element is 'item_2'" "item_2" "$RESULT"
echo ""

# Test 9: BatchDelete with overflow (clamp)
echo "Test 9: BatchDelete with overflow (clamp)"
TList.new mylist9
for (( i = 0; i < 5; i++ )); do
    mylist9.Add "item_$i"
done
mylist9.BatchDelete 2 10
test_result "Count is 2 after BatchDelete with overflow" "2" "$RESULT"
echo ""

# Test 10: BatchDelete with count=0 (no-op)
echo "Test 10: BatchDelete with count=0 (no-op)"
TList.new mylist10
mylist10.Add "a"
mylist10.Add "b"
mylist10.BatchDelete 0 0
test_result "Count remains 2 after BatchDelete with count=0" "2" "$RESULT"
echo ""

# Test 11: BatchInsert out of bounds
echo "Test 11: BatchInsert out of bounds"
TList.new mylist11
mylist11.Add "a"
mylist11.BatchInsert 5 "x"
if [[ $? -eq 1 ]]; then
    echo -e "${GREEN}✓${NC} BatchInsert out of bounds returns error"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} BatchInsert out of bounds should return error"
    ((TESTS_FAILED++))
fi
echo ""

# Test 12: BatchDelete out of bounds
echo "Test 12: BatchDelete out of bounds"
TList.new mylist12
mylist12.Add "a"
mylist12.BatchDelete 5 1
if [[ $? -eq 1 ]]; then
    echo -e "${GREEN}✓${NC} BatchDelete out of bounds returns error"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} BatchDelete out of bounds should return error"
    ((TESTS_FAILED++))
fi
echo ""

# Test 13: Alternating batch operations
echo "Test 13: Alternating batch operations"
TList.new mylist13
for (( i = 0; i < 3; i++ )); do
    mylist13.Add "a_$i"
done
mylist13.BatchInsert 1 "x" "y"
mylist13.BatchDelete 2 1
mylist13.BatchInsert 3 "p" "q"
count=$(mylist13.count)
test_result "Count after alternating operations is 7" "7" "$count"
echo ""

# Test 14: Integration with existing methods
echo "Test 14: Integration with existing methods"
TList.new mylist14
mylist14.Add "a"
mylist14.Add "b"
mylist14.BatchInsert 1 "x" "y" "z"
mylist14.Delete 2
mylist14.Insert 0 "first"
count=$(mylist14.count)
test_result "Count after mixed operations is 6" "6" "$count"
echo ""

echo "=== Test Results ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo "Total:  $((TESTS_PASSED + TESTS_FAILED))"

if [[ $TESTS_FAILED -eq 0 ]]; then
    exit 0
else
    exit 1
fi
