#!/bin/bash
# 002_AddAndRetrievalOperations.sh - Test Add, Get, and retrieval operations
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tstringlist module
TSTRINGLIST_DIR="$SCRIPT_DIR/.."
source "$TSTRINGLIST_DIR/tstringlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Initialize test-specific temp directory

kk_test_section "002: Add and Retrieval Operations"

# Create TStringList instance
TStringList.new mylist

# Test: Add single string
kk_test_start "Add single string"
mylist.Add "apple" >/dev/null
count=$(mylist.count)
if [[ "$count" == "1" ]]; then
    kk_test_pass "Added string, count is 1"
else
    kk_test_fail "Count is $count, expected 1"
fi

# Test: Add second string
kk_test_start "Add second string"
mylist.Add "banana" >/dev/null
count=$(mylist.count)
if [[ "$count" == "2" ]]; then
    kk_test_pass "Count is 2 after adding two strings"
else
    kk_test_fail "Count is $count, expected 2"
fi

# Test: Add third string
kk_test_start "Add third string"
mylist.Add "cherry" >/dev/null
count=$(mylist.count)
if [[ "$count" == "3" ]]; then
    kk_test_pass "Count is 3 after adding three strings"
else
    kk_test_fail "Count is $count, expected 3"
fi

# Test: Get string at index 0
kk_test_start "Get string at index 0"
item=$(mylist.Get 0)
if [[ "$item" == "apple" ]]; then
    kk_test_pass "Get(0) returned 'apple'"
else
    kk_test_fail "Get(0) returned '$item', expected 'apple'"
fi

# Test: Get string at index 1
kk_test_start "Get string at index 1"
item=$(mylist.Get 1)
if [[ "$item" == "banana" ]]; then
    kk_test_pass "Get(1) returned 'banana'"
else
    kk_test_fail "Get(1) returned '$item', expected 'banana'"
fi

# Test: Get string at index 2
kk_test_start "Get string at index 2"
item=$(mylist.Get 2)
if [[ "$item" == "cherry" ]]; then
    kk_test_pass "Get(2) returned 'cherry'"
else
    kk_test_fail "Get(2) returned '$item', expected 'cherry'"
fi

# Test: Get with invalid index (out of bounds)
kk_test_start "Get with invalid index (should fail)"
TRAP_ERRORS_ENABLED=false
item=$(mylist.Get 5 2>&1)
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kk_test_pass "Get(5) correctly failed for out of bounds"
else
    kk_test_fail "Get(5) should have failed"
fi

# Test: Add many strings for capacity growth
kk_test_start "Add many strings to test capacity growth"
for i in {4..20}; do
    mylist.Add "item$i" >/dev/null
done
final_count=$(mylist.count)
final_capacity=$(mylist.capacity)
if [[ "$final_count" == "20" && "$final_capacity" -ge "$final_count" ]]; then
    kk_test_pass "Added 20 items, capacity grew appropriately"
else
    kk_test_fail "Count: $final_count (expected 20), Capacity: $final_capacity"
fi

# Test: Verify first and last items
kk_test_start "Verify first and last items"
first=$(mylist.Get 0)
last=$(mylist.Get 19)
if [[ "$first" == "apple" && "$last" == "item20" ]]; then
    kk_test_pass "First and last items are correct"
else
    kk_test_fail "First: '$first' (expected 'apple'), Last: '$last' (expected 'item20')"
fi

# Cleanup
mylist.delete

kk_test_log "002_AddAndRetrievalOperations.sh completed"
