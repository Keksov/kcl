#!/bin/bash
# 002_AddAndBasicOperations.sh - Test Add method and basic operations
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

kk_test_section "002: Add Method and Basic Operations"

# Create TList instance
TList.new mylist

# Test: Add single item
kk_test_start "Add single item"
mylist.Add "item1"
count=$(mylist.count)
if [[ "$count" == "1" ]]; then
    # Verify content
    declare -n items_ref="mylist_items"
    if [[ "${items_ref[0]}" == "item1" ]]; then
        kk_test_pass "Added item and content verified"
    else
        kk_test_fail "Item content incorrect: ${items_ref[0]}"
    fi
else
    kk_test_fail "Count is $count, expected 1"
fi

# Test: Add second item
kk_test_start "Add second item"
mylist.Add "item2"
count=$(mylist.count)
if [[ "$count" == "2" ]]; then
    # Verify both items
    declare -n items_ref="mylist_items"
    if [[ "${items_ref[0]}" == "item1" && "${items_ref[1]}" == "item2" ]]; then
        kk_test_pass "Added second item and content verified"
    else
        kk_test_fail "Items incorrect: [0]=${items_ref[0]}, [1]=${items_ref[1]}"
    fi
else
    kk_test_fail "Count is $count, expected 2"
fi

# Test: Add with null check
kk_test_start "Add empty item"
mylist.Add ""
count=$(mylist.count)
if [[ "$count" == "3" ]]; then
    # Verify empty item
    declare -n items_ref="mylist_items"
    if [[ "${items_ref[2]}" == "" ]]; then
        kk_test_pass "Empty item added correctly"
    else
        kk_test_fail "Empty item not stored correctly: ${items_ref[2]}"
    fi
else
    kk_test_fail "Count mismatch after adding empty item: $count"
fi

# Test: First and Last methods
kk_test_start "Test First and Last methods"
mylist.First
first_item="$RESULT"
mylist.Last
last_item="$RESULT"
if [[ "$first_item" == "item1" && "$last_item" == "" ]]; then
    kk_test_pass "First and Last methods work correctly"
else
    kk_test_fail "First/Last incorrect: first='$first_item', last='$last_item'"
fi

# Cleanup
mylist.delete

kk_test_log "002_AddAndBasicOperations.sh completed"
