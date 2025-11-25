#!/bin/bash
# 001_BasicCreationAndDestruction.sh - Test basic TList creation and destruction
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tlist module
TLIST_DIR="$SCRIPT_DIR/.."
source "$TLIST_DIR/tlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

# Initialize test-specific temp directory

kk_test_section "001: Basic TList Creation and Destruction"

# Test: Create a TList instance
kk_test_start "Create TList instance"
TList.new mylist
if [[ -n "$(mylist.count)" ]]; then
    kk_test_pass "TList instance created successfully"
else
    kk_test_fail "Failed to create TList instance"
fi

# Test: Check initial state
kk_test_start "Check initial count"
count=$(mylist.count)
if [[ "$count" == "0" ]]; then
    kk_test_pass "Initial count is 0"
else
    kk_test_fail "Initial count is $count, expected 0"
fi

kk_test_start "Check initial capacity"
capacity=$(mylist.capacity)
if [[ "$capacity" == "0" ]]; then
    kk_test_pass "Initial Capacity is 0"
else
    kk_test_fail "Initial Capacity is $capacity, expected 0"
fi

# Test: Destroy the instance
kk_test_start "Destroy TList instance"
mylist.delete
result=$?
if [[ $result -eq 0 ]]; then
    kk_test_pass "TList instance destroyed successfully"
else
    kk_test_fail "Failed to destroy TList instance"
fi

# Test: Create multiple instances
kk_test_start "Create multiple TList instances"
TList.new list1
TList.new list2
count1=$(list1.count 2>/dev/null)
count2=$(list2.count 2>/dev/null)
if [[ -n "$count1" && -n "$count2" ]]; then
    kk_test_pass "Multiple TList instances created successfully"
else
    kk_test_fail "Failed to create multiple TList instances"
fi

# Destroy them
list1.delete
list2.delete

# Test: Attempt to access destroyed instance (should fail gracefully)
kk_test_start "Access destroyed instance"
TRAP_ERRORS_ENABLED=false
list1.count >/dev/null 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kk_test_pass "Destroyed instance properly inaccessible"
else
    kk_test_fail "Destroyed instance still accessible"
fi

kk_test_log "001_BasicCreationAndDestruction.sh completed"
