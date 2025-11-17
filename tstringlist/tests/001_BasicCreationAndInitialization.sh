#!/bin/bash
# 001_BasicCreationAndInitialization.sh - Test TStringList creation and initialization
# Tests the basic creation, destruction, and initial state of TStringList instances

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "001"

test_section "001: TStringList Basic Creation and Initialization"

# Test: Create TStringList instance
test_start "Create TStringList instance"
TStringList.new mylist
if [[ -n "$(mylist.count)" ]]; then
    test_pass "TStringList instance created successfully"
else
    test_fail "Failed to create TStringList instance"
fi

# Test: Check initial count
test_start "Check initial count is 0"
count=$(mylist.count)
if [[ "$count" == "0" ]]; then
    test_pass "Initial count is 0"
else
    test_fail "Initial count is $count, expected 0"
fi

# Test: Check initial capacity
test_start "Check initial capacity"
capacity=$(mylist.capacity)
if [[ "$capacity" == "0" ]]; then
    test_pass "Initial capacity is 0"
else
    test_fail "Initial capacity is $capacity, expected 0"
fi

# Test: Check initial case_sensitive property
test_start "Check initial case_sensitive property (should be false)"
if [[ "$(mylist.case_sensitive)" == "false" ]]; then
    test_pass "case_sensitive is false by default"
else
    test_fail "case_sensitive is $(mylist.case_sensitive), expected false"
fi

# Test: Check initial sorted property
test_start "Check initial sorted property (should be false)"
if [[ "$(mylist.sorted)" == "false" ]]; then
    test_pass "sorted is false by default"
else
    test_fail "sorted is $(mylist.sorted), expected false"
fi

# Test: Check initial duplicates property
test_start "Check initial duplicates property (should be dupAccept)"
if [[ "$(mylist.duplicates)" == "dupAccept" ]]; then
    test_pass "duplicates is dupAccept by default"
else
    test_fail "duplicates is $(mylist.duplicates), expected dupAccept"
fi

# Test: Destroy the instance
test_start "Destroy TStringList instance"
mylist.delete
result=$?
if [[ $result -eq 0 ]]; then
    test_pass "TStringList instance destroyed successfully"
else
    test_fail "Failed to destroy TStringList instance"
fi

# Test: Create multiple TStringList instances
test_start "Create multiple TStringList instances"
TStringList.new list1
TStringList.new list2
TStringList.new list3
count1=$(list1.count 2>/dev/null)
count2=$(list2.count 2>/dev/null)
count3=$(list3.count 2>/dev/null)
if [[ -n "$count1" && -n "$count2" && -n "$count3" ]]; then
    test_pass "Multiple TStringList instances created successfully"
else
    test_fail "Failed to create multiple TStringList instances"
fi

# Test: Verify independent instances
test_start "Verify instances are independent"
list1.Add "list1_item"
list2.Add "list2_item"
count1=$(list1.count)
count2=$(list2.count)
if [[ "$count1" == "1" && "$count2" == "1" ]]; then
    test_pass "Instances are independent"
else
    test_fail "Instances are not independent: list1.count=$count1, list2.count=$count2"
fi

# Destroy them
list1.delete
list2.delete
list3.delete

test_info "001_BasicCreationAndInitialization.sh completed"
