#!/bin/bash
# 003_PutAndModificationOperations.sh - Test Put method and string modifications
# Tests replacing strings at specific positions

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "003"

test_section "003: Put and Modification Operations"

# Create TStringList instance with some initial data
TStringList.new mylist
mylist.Add "apple"
mylist.Add "banana"
mylist.Add "cherry"
mylist.Add "date"
mylist.Add "elderberry"

# Test: Put (replace) string at index 0
test_start "Put string at index 0"
mylist.Put 0 "apricot"
item=$(mylist.Get 0)
if [[ "$item" == "apricot" ]]; then
    test_pass "Put(0) replaced item successfully"
else
    test_fail "Put(0) returned '$item', expected 'apricot'"
fi

# Test: Verify other items are unchanged
test_start "Verify other items unchanged after Put"
item1=$(mylist.Get 1)
item2=$(mylist.Get 2)
if [[ "$item1" == "banana" && "$item2" == "cherry" ]]; then
    test_pass "Other items are unchanged"
else
    test_fail "Items changed: item1='$item1', item2='$item2'"
fi

# Test: Put string at middle index
test_start "Put string at middle index"
mylist.Put 2 "grape"
item=$(mylist.Get 2)
if [[ "$item" == "grape" ]]; then
    test_pass "Put(2) replaced item successfully"
else
    test_fail "Put(2) returned '$item', expected 'grape'"
fi

# Test: Put string at last index
test_start "Put string at last index"
mylist.Put 4 "fig"
item=$(mylist.Get 4)
if [[ "$item" == "fig" ]]; then
    test_pass "Put(4) replaced item at last position"
else
    test_fail "Put(4) returned '$item', expected 'fig'"
fi

# Test: Count should remain unchanged after Put operations
test_start "Count unchanged after Put operations"
count=$(mylist.count)
if [[ "$count" == "5" ]]; then
    test_pass "Count is still 5 after Put operations"
else
    test_fail "Count is $count, expected 5"
fi

# Test: Put with invalid index (out of bounds - negative)
test_start "Put with invalid index (negative, should fail)"
TRAP_ERRORS_ENABLED=false
mylist.Put -1 "kiwi" 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    test_pass "Put(-1) correctly failed for negative index"
else
    test_fail "Put(-1) should have failed"
fi

# Test: Put with invalid index (out of bounds - too large)
test_start "Put with invalid index (too large, should fail)"
TRAP_ERRORS_ENABLED=false
mylist.Put 100 "lemon" 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    test_pass "Put(100) correctly failed for out of bounds"
else
    test_fail "Put(100) should have failed"
fi

# Test: Put with empty string
test_start "Put empty string at index"
mylist.Put 1 ""
item=$(mylist.Get 1)
if [[ "$item" == "" ]]; then
    test_pass "Put(1) with empty string succeeded"
else
    test_fail "Put(1) returned '$item', expected empty string"
fi

# Test: Put string with special characters
test_start "Put string with special characters"
mylist.Put 3 "hello@world#123"
item=$(mylist.Get 3)
if [[ "$item" == "hello@world#123" ]]; then
    test_pass "Put with special characters succeeded"
else
    test_fail "Put returned '$item', expected 'hello@world#123'"
fi

# Cleanup
mylist.delete

test_info "003_PutAndModificationOperations.sh completed"
