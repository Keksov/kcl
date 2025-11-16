#!/bin/bash
# 001_BasicCreationAndDestruction.sh - Test basic TList creation and destruction

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "001"

test_section "001: Basic TList Creation and Destruction"

# Test: Create a TList instance
test_start "Create TList instance"
TList.new mylist
if [[ -n "$(mylist.count)" ]]; then
    test_pass "TList instance created successfully"
else
    test_fail "Failed to create TList instance"
fi

# Test: Check initial state
test_start "Check initial count"
count=$(mylist.count)
if [[ "$count" == "0" ]]; then
    test_pass "Initial count is 0"
else
    test_fail "Initial count is $count, expected 0"
fi

test_start "Check initial capacity"
capacity=$(mylist.capacity)
if [[ "$capacity" == "0" ]]; then
    test_pass "Initial Capacity is 0"
else
    test_fail "Initial Capacity is $capacity, expected 0"
fi

# Test: Destroy the instance
test_start "Destroy TList instance"
mylist.delete
result=$?
if [[ $result -eq 0 ]]; then
    test_pass "TList instance destroyed successfully"
else
    test_fail "Failed to destroy TList instance"
fi

# Test: Create multiple instances
test_start "Create multiple TList instances"
TList.new list1
TList.new list2
count1=$(list1.count 2>/dev/null)
count2=$(list2.count 2>/dev/null)
if [[ -n "$count1" && -n "$count2" ]]; then
    test_pass "Multiple TList instances created successfully"
else
    test_fail "Failed to create multiple TList instances"
fi

# Destroy them
list1.delete
list2.delete

# Test: Attempt to access destroyed instance (should fail gracefully)
test_start "Access destroyed instance"
TRAP_ERRORS_ENABLED=false
list1.count >/dev/null 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    test_pass "Destroyed instance properly inaccessible"
else
    test_fail "Destroyed instance still accessible"
fi

test_info "001_BasicCreationAndDestruction.sh completed"