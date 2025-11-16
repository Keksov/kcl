#!/bin/bash
# 011_move_operations.sh - Test Move method

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "011"

test_section "011: Move Operations"

# Create TList instance and add items
TList.new mylist
mylist.Add "zero"
mylist.Add "one"
mylist.Add "two"
mylist.Add "three"
mylist.Add "four"

# Test: Move item forward
test_start "Move item forward"
mylist.Move 1 3  # Move "one" from index 1 to index 3
items_var="mylist_items"
declare -n items_ref="$items_var"
# Should now be: zero, two, three, one, four
if [[ "${items_ref[0]}" == "zero" && "${items_ref[1]}" == "two" && "${items_ref[2]}" == "three" && "${items_ref[3]}" == "one" && "${items_ref[4]}" == "four" ]]; then
    test_pass "Moved item from index 1 to 3"
else
    test_fail "After move 1->3: [0]='${items_ref[0]}', [1]='${items_ref[1]}', [2]='${items_ref[2]}', [3]='${items_ref[3]}', [4]='${items_ref[4]}'"
fi

# Test: Move item backward
test_start "Move item backward"
mylist.Move 3 1  # Move "one" from index 3 to index 1
declare -n items_ref="$items_var"
# Should now be: zero, one, two, three, four
if [[ "${items_ref[0]}" == "zero" && "${items_ref[1]}" == "one" && "${items_ref[2]}" == "two" && "${items_ref[3]}" == "three" && "${items_ref[4]}" == "four" ]]; then
    test_pass "Moved item from index 3 to 1"
else
    test_fail "After move 3->1: [0]='${items_ref[0]}', [1]='${items_ref[1]}', [2]='${items_ref[2]}', [3]='${items_ref[3]}', [4]='${items_ref[4]}'"
fi

# Test: Move to same position (should do nothing)
test_start "Move to same position"
mylist.Move 2 2
declare -n items_ref="$items_var"
if [[ "${items_ref[2]}" == "two" ]]; then
    test_pass "Move to same position does nothing"
else
    test_fail "Move to same position changed items"
fi

# Test: Move first to last
test_start "Move first to last"
mylist.Move 0 4
declare -n items_ref="$items_var"
# Should now be: one, two, three, four, zero
if [[ "${items_ref[0]}" == "one" && "${items_ref[1]}" == "two" && "${items_ref[2]}" == "three" && "${items_ref[3]}" == "four" && "${items_ref[4]}" == "zero" ]]; then
    test_pass "Moved first item to last position"
else
    test_fail "After move 0->4: [0]='${items_ref[0]}', [1]='${items_ref[1]}', [2]='${items_ref[2]}', [3]='${items_ref[3]}', [4]='${items_ref[4]}'"
fi

# Test: Move out of bounds (should handle gracefully)
test_start "Move out of bounds"
TRAP_ERRORS_ENABLED=false
mylist.Move 0 10
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    test_pass "Move out of bounds handled gracefully"
else
    test_fail "Move out of bounds should return error"
fi

# Test: Move negative index
test_start "Move negative index"
TRAP_ERRORS_ENABLED=false
mylist.Move -1 2
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    test_pass "Move negative index handled gracefully"
else
    test_fail "Move negative index should return error"
fi

# Cleanup
mylist.delete

test_info "011_move_operations.sh completed"
