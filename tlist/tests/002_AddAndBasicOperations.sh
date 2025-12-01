#!/bin/bash
# 002_AddAndBasicOperations.sh - Test Add method and basic operations
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tlist module
TLIST_DIR="$SCRIPT_DIR/.."
source "$TLIST_DIR/tlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "002: Add Method and Basic Operations"

# Create TList instance
TList.new mylist

# Test: Add single item
kt_test_start "Add single item"
mylist.Add "item1"
count=$(mylist.count)
if [[ "$count" == "1" ]]; then
    # Verify content
    declare -n items_ref="mylist_items"
    if [[ "${items_ref[0]}" == "item1" ]]; then
        kt_test_pass "Added item and content verified"
    else
        kt_test_fail "Item content incorrect: ${items_ref[0]}"
    fi
else
    kt_test_fail "Count is $count, expected 1"
fi

# Test: Add second item
kt_test_start "Add second item"
mylist.Add "item2"
count=$(mylist.count)
if [[ "$count" == "2" ]]; then
    # Verify both items
    declare -n items_ref="mylist_items"
    if [[ "${items_ref[0]}" == "item1" && "${items_ref[1]}" == "item2" ]]; then
        kt_test_pass "Added second item and content verified"
    else
        kt_test_fail "Items incorrect: [0]=${items_ref[0]}, [1]=${items_ref[1]}"
    fi
else
    kt_test_fail "Count is $count, expected 2"
fi

# Test: Add with null check
kt_test_start "Add empty item"
mylist.Add ""
count=$(mylist.count)
if [[ "$count" == "3" ]]; then
    # Verify empty item
    declare -n items_ref="mylist_items"
    if [[ "${items_ref[2]}" == "" ]]; then
        kt_test_pass "Empty item added correctly"
    else
        kt_test_fail "Empty item not stored correctly: ${items_ref[2]}"
    fi
else
    kt_test_fail "Count mismatch after adding empty item: $count"
fi

# Test: First and Last methods
kt_test_start "Test First and Last methods"
mylist.First
first_item="$RESULT"
mylist.Last
last_item="$RESULT"
if [[ "$first_item" == "item1" && "$last_item" == "" ]]; then
    kt_test_pass "First and Last methods work correctly"
else
    kt_test_fail "First/Last incorrect: first='$first_item', last='$last_item'"
fi

# Cleanup
mylist.delete

kt_test_log "002_AddAndBasicOperations.sh completed"
