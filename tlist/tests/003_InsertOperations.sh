#!/bin/bash
# 003_insert_operations.sh - Test Insert method

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "003"

test_section "003: Insert Operations"

# Create TList instance
TList.new mylist

# Add some initial items
mylist.Add "item1"
mylist.Add "item3"
mylist.Add "item4"

# Test: Insert at beginning
test_start "Insert at index 0"
mylist.Insert 0 "item0"
count=$(mylist.count)
if [[ "$count" == "4" ]]; then
    mylist.First && first=$RESULT
    if [[ "$first" == "item0" ]]; then
        test_pass "Inserted at index 0 correctly"
    else
        test_fail "First item is '$first', expected 'item0'"
    fi
else
    test_fail "Count is $count, expected 4"
fi

# Test: Insert in middle
test_start "Insert in middle"
mylist.Insert 2 "item2"
count=$(mylist.count)
if [[ "$count" == "5" ]]; then
    # Check items: item0, item1, item2, item3, item4
    items_var="mylist_items"
    declare -n items_ref="$items_var"
    if [[ "${items_ref[2]}" == "item2" ]]; then
        test_pass "Inserted in middle correctly"
    else
        test_fail "Item at index 2 is '${items_ref[2]}', expected 'item2'"
    fi
else
    test_fail "Count is $count, expected 5"
fi

# Test: Insert at end (should work like Add)
test_start "Insert at end"
mylist.Insert 5 "item5"
count=$(mylist.count)
mylist.Last && last=$RESULT
if [[ "$count" == "6" && "$last" == "item5" ]]; then
    test_pass "Inserted at end correctly"
else
    test_fail "Count: $count (expected 6), Last: '$last' (expected 'item5')"
fi

# Test: Insert out of bounds (should fail)
test_start "Insert out of bounds (high)"
TRAP_ERRORS_ENABLED=false
mylist.Insert 10 "invalid"
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    test_pass "Insert out of bounds returned error"
else
    test_fail "Insert out of bounds should fail"
fi

# Test: Insert negative index (should fail)
test_start "Insert negative index"
TRAP_ERRORS_ENABLED=false
mylist.Insert -1 "invalid"
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    test_pass "Insert negative index returned error"
else
    test_fail "Insert negative index should fail"
fi

# Cleanup
mylist.delete

test_info "003_insert_operations.sh completed"
