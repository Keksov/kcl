#!/bin/bash
# 012_pack_operations.sh - Test Pack method

# Source common.sh for shared code
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "012"

test_section "012: Pack Operations"

# Create TList instance
TList.new mylist

# Add items including empty ones
mylist.Add "item1"
mylist.Add ""      # empty
mylist.Add "item2"
mylist.Add ""      # empty
mylist.Add ""      # empty
mylist.Add "item3"

initial_count=$(mylist.count)
initial_capacity=$(mylist.capacity)

# Test: Pack the list
test_start "Pack list with empty items"
mylist.Pack
count=$(mylist.count)
capacity=$(mylist.capacity)

# Should remove empty items: item1, item2, item3 (3 items)
if [[ "$count" == "3" ]]; then
    items_var="mylist_items"
    declare -n items_ref="$items_var"
    if [[ "${items_ref[0]}" == "item1" && "${items_ref[1]}" == "item2" && "${items_ref[2]}" == "item3" ]]; then
        test_pass "Pack removed empty items correctly"
    else
        test_fail "Items after pack: [0]='${items_ref[0]}', [1]='${items_ref[1]}', [2]='${items_ref[2]}'"
    fi
else
    test_fail "Count after pack: $count (expected 3)"
fi

# Test: Capacity after pack
test_start "Capacity after pack"
# Capacity should still be the same or larger
if [[ "$capacity" -ge "$count" ]]; then
    test_pass "Capacity after pack is adequate"
else
    test_fail "Capacity $capacity < Count $count after pack"
fi

# Test: Pack list with no empty items
test_start "Pack list with no empty items"
mylist.Pack
count_after=$(mylist.count)
if [[ "$count_after" == "3" ]]; then
    test_pass "Pack on list with no empty items does nothing"
else
    test_fail "Count changed after pack on full list: $count_after (expected 3)"
fi

# Test: Pack empty list
test_start "Pack empty list"
TList.new emptylist
emptylist.Pack
count=$(emptylist.count)
if [[ "$count" == "0" ]]; then
    test_pass "Pack empty list works"
else
    test_fail "Pack empty list changed count to $count"
fi
emptylist.delete

# Test: Pack list with all empty items
test_start "Pack list with all empty items"
TList.new allemptylist
allemptylist.Add ""
allemptylist.Add ""
allemptylist.Add ""
allemptylist.Pack
count=$(allemptylist.count)
if [[ "$count" == "0" ]]; then
    test_pass "Pack list with all empty items results in empty list"
else
    test_fail "Pack all-empty list left count $count"
fi
allemptylist.delete

# Test: Pack after count assignment (which adds empty items)
test_start "Pack after count assignment"
mylist.count = "10"  # Adds 7 empty items
mylist.Pack
count=$(mylist.count)
if [[ "$count" == "3" ]]; then
    test_pass "Pack after count assignment removes added empty items"
else
    test_fail "Count after pack: $count (expected 3)"
fi

# Cleanup
mylist.delete

test_info "012_pack_operations.sh completed"
