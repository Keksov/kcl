#!/bin/bash
# 010_exchange_operations.sh - Test Exchange method

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Initialize test-specific temp directory
init_test_tmpdir "010"

test_section "010: Exchange Operations"

# Create TList instance and add items
TList.new mylist
mylist.Add "first"
mylist.Add "second"
mylist.Add "third"
mylist.Add "fourth"

# Test: Exchange adjacent items
test_start "Exchange adjacent items"
mylist.Exchange 1 2
items_var="mylist_items"
declare -n items_ref="$items_var"
if [[ "${items_ref[0]}" == "first" && "${items_ref[1]}" == "third" && "${items_ref[2]}" == "second" && "${items_ref[3]}" == "fourth" ]]; then
    test_pass "Exchanged indices 1 and 2"
else
    test_fail "After exchange 1<->2: [0]='${items_ref[0]}', [1]='${items_ref[1]}', [2]='${items_ref[2]}', [3]='${items_ref[3]}'"
fi

# Test: Exchange first and last
test_start "Exchange first and last"
mylist.Exchange 0 3
declare -n items_ref="$items_var"
if [[ "${items_ref[0]}" == "fourth" && "${items_ref[1]}" == "third" && "${items_ref[2]}" == "second" && "${items_ref[3]}" == "first" ]]; then
    test_pass "Exchanged indices 0 and 3"
else
    test_fail "After exchange 0<->3: [0]='${items_ref[0]}', [1]='${items_ref[1]}', [2]='${items_ref[2]}', [3]='${items_ref[3]}'"
fi

# Test: Exchange same index (should do nothing)
test_start "Exchange same index"
original_first="${items_ref[0]}"
mylist.Exchange 1 1
if [[ "${items_ref[0]}" == "$original_first" ]]; then
    test_pass "Exchange same index does nothing"
else
    test_fail "Exchange same index changed items"
fi

# Test: Exchange out of bounds (should handle gracefully)
test_start "Exchange out of bounds"
mylist.Exchange 0 10 2>/dev/null
result=$?
if [[ $result -ne 0 ]]; then
    test_pass "Exchange out of bounds handled gracefully"
else
    test_fail "Exchange out of bounds should return error"
fi

# Test: Exchange negative index
test_start "Exchange negative index"
mylist.Exchange -1 2 2>/dev/null
result=$?
if [[ $result -ne 0 ]]; then
    test_pass "Exchange negative index handled gracefully"
else
    test_fail "Exchange negative index should return error"
fi

# Test: Exchange on single item list
test_start "Exchange on single item list"
TList.new singlelist
singlelist.Add "only"
singlelist.Exchange 0 0
if [[ "$(singlelist.First)" == "only" ]]; then
    test_pass "Exchange on single item list works"
else
    test_fail "Exchange on single item changed the item"
fi
singlelist.delete

# Cleanup
mylist.delete

test_info "010_exchange_operations.sh completed"
