#!/bin/bash
# 002_AddAndRetrievalOperations.sh - Test Add, Get, and retrieval operations
# Tests adding strings and retrieving them from the list

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "002"

test_section "002: Add and Retrieval Operations"

# Create TStringList instance
TStringList.new mylist

# Test: Add single string
test_start "Add single string"
mylist.Add "apple" >/dev/null
count=$(mylist.count)
if [[ "$count" == "1" ]]; then
    test_pass "Added string, count is 1"
else
    test_fail "Count is $count, expected 1"
fi

# Test: Add second string
test_start "Add second string"
mylist.Add "banana" >/dev/null
count=$(mylist.count)
if [[ "$count" == "2" ]]; then
    test_pass "Count is 2 after adding two strings"
else
    test_fail "Count is $count, expected 2"
fi

# Test: Add third string
test_start "Add third string"
mylist.Add "cherry" >/dev/null
count=$(mylist.count)
if [[ "$count" == "3" ]]; then
    test_pass "Count is 3 after adding three strings"
else
    test_fail "Count is $count, expected 3"
fi

# Test: Get string at index 0
test_start "Get string at index 0"
item=$(mylist.Get 0)
if [[ "$item" == "apple" ]]; then
    test_pass "Get(0) returned 'apple'"
else
    test_fail "Get(0) returned '$item', expected 'apple'"
fi

# Test: Get string at index 1
test_start "Get string at index 1"
item=$(mylist.Get 1)
if [[ "$item" == "banana" ]]; then
    test_pass "Get(1) returned 'banana'"
else
    test_fail "Get(1) returned '$item', expected 'banana'"
fi

# Test: Get string at index 2
test_start "Get string at index 2"
item=$(mylist.Get 2)
if [[ "$item" == "cherry" ]]; then
    test_pass "Get(2) returned 'cherry'"
else
    test_fail "Get(2) returned '$item', expected 'cherry'"
fi

# Test: Get with invalid index (out of bounds)
test_start "Get with invalid index (should fail)"
TRAP_ERRORS_ENABLED=false
item=$(mylist.Get 5 2>&1)
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    test_pass "Get(5) correctly failed for out of bounds"
else
    test_fail "Get(5) should have failed"
fi

# Test: Add many strings for capacity growth
test_start "Add many strings to test capacity growth"
for i in {4..20}; do
    mylist.Add "item$i" >/dev/null
done
final_count=$(mylist.count)
final_capacity=$(mylist.capacity)
if [[ "$final_count" == "20" && "$final_capacity" -ge "$final_count" ]]; then
    test_pass "Added 20 items, capacity grew appropriately"
else
    test_fail "Count: $final_count (expected 20), Capacity: $final_capacity"
fi

# Test: Verify first and last items
test_start "Verify first and last items"
first=$(mylist.Get 0)
last=$(mylist.Get 19)
if [[ "$first" == "apple" && "$last" == "item20" ]]; then
    test_pass "First and last items are correct"
else
    test_fail "First: '$first' (expected 'apple'), Last: '$last' (expected 'item20')"
fi

# Cleanup
mylist.delete

test_info "002_AddAndRetrievalOperations.sh completed"
