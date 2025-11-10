#!/bin/bash
# 001_BasicCreationAndDestruction.sh - Test basic TList creation and destruction

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Initialize test-specific temp directory
init_test_tmpdir "001"

test_section "001: Basic TList Creation and Destruction"

# Test: Create a TList instance
test_start "Create TList instance"
TList.new mylist
if declare -f mylist.Count >/dev/null 2>&1; then
    test_pass "TList instance created successfully"
else
    test_fail "Failed to create TList instance"
fi

# Test: Check initial state
test_start "Check initial Count"
count=$(mylist.Count)
if [[ "$count" == "0" ]]; then
    test_pass "Initial Count is 0"
else
    test_fail "Initial Count is $count, expected 0"
fi

test_start "Check initial Capacity"
capacity=$(mylist.Capacity)
if [[ "$capacity" == "0" ]]; then
    test_pass "Initial Capacity is 0"
else
    test_fail "Initial Capacity is $capacity, expected 0"
fi

# Test: Destroy the instance
test_start "Destroy TList instance"
mylist.delete
if ! declare -f mylist.Count >/dev/null 2>&1; then
    test_pass "TList instance destroyed successfully"
else
    test_fail "Failed to destroy TList instance"
fi

# Test: Create multiple instances
test_start "Create multiple TList instances"
TList.new list1
TList.new list2
if declare -f list1.Count >/dev/null 2>&1 && declare -f list2.Count >/dev/null 2>&1; then
    test_pass "Multiple TList instances created successfully"
else
    test_fail "Failed to create multiple TList instances"
fi

# Destroy them
list1.delete
list2.delete

# Test: Attempt to access destroyed instance (should fail gracefully)
test_start "Access destroyed instance"
if ! declare -f list1.Count >/dev/null 2>&1; then
    test_pass "Destroyed instance properly inaccessible"
else
    test_fail "Destroyed instance still accessible"
fi

test_info "001_BasicCreationAndDestruction.sh completed"