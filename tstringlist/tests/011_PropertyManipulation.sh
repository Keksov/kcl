#!/bin/bash
# 011_PropertyManipulation.sh - Test property get/set operations
# Tests manipulating case_sensitive, sorted, and duplicates properties

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Initialize test-specific temp directory
init_test_tmpdir "011"

test_section "011: Property Manipulation"

# Test: Get case_sensitive property
test_start "Get case_sensitive property"
TStringList.new mylist
prop=$(mylist.case_sensitive)
if [[ "$prop" == "false" ]]; then
    test_pass "case_sensitive is 'false' by default"
else
    test_fail "case_sensitive is '$prop', expected 'false'"
fi

# Test: Set case_sensitive to true
test_start "Set case_sensitive to true"
mylist.case_sensitive = "true"
prop=$(mylist.case_sensitive)
if [[ "$prop" == "true" ]]; then
    test_pass "case_sensitive set to 'true'"
else
    test_fail "case_sensitive is '$prop', expected 'true'"
fi

# Test: Set case_sensitive to false
test_start "Set case_sensitive to false"
mylist.case_sensitive = "false"
prop=$(mylist.case_sensitive)
if [[ "$prop" == "false" ]]; then
    test_pass "case_sensitive set to 'false'"
else
    test_fail "case_sensitive is '$prop', expected 'false'"
fi

# Test: Get sorted property
test_start "Get sorted property"
prop=$(mylist.sorted)
if [[ "$prop" == "false" ]]; then
    test_pass "sorted is 'false' by default"
else
    test_fail "sorted is '$prop', expected 'false'"
fi

# Test: Set sorted to true
test_start "Set sorted to true"
mylist.sorted = "true"
prop=$(mylist.sorted)
if [[ "$prop" == "true" ]]; then
    test_pass "sorted set to 'true'"
else
    test_fail "sorted is '$prop', expected 'true'"
fi

# Test: Set sorted to false
test_start "Set sorted to false"
mylist.sorted = "false"
prop=$(mylist.sorted)
if [[ "$prop" == "false" ]]; then
    test_pass "sorted set to 'false'"
else
    test_fail "sorted is '$prop', expected 'false'"
fi

# Test: Get duplicates property
test_start "Get duplicates property"
prop=$(mylist.duplicates)
if [[ "$prop" == "dupAccept" ]]; then
    test_pass "duplicates is 'dupAccept' by default"
else
    test_fail "duplicates is '$prop', expected 'dupAccept'"
fi

# Test: Set duplicates to dupIgnore
test_start "Set duplicates to dupIgnore"
mylist.duplicates = "dupIgnore"
prop=$(mylist.duplicates)
if [[ "$prop" == "dupIgnore" ]]; then
    test_pass "duplicates set to 'dupIgnore'"
else
    test_fail "duplicates is '$prop', expected 'dupIgnore'"
fi

# Test: Set duplicates to dupError
test_start "Set duplicates to dupError"
mylist.duplicates = "dupError"
prop=$(mylist.duplicates)
if [[ "$prop" == "dupError" ]]; then
    test_pass "duplicates set to 'dupError'"
else
    test_fail "duplicates is '$prop', expected 'dupError'"
fi

# Test: Set duplicates to dupAccept
test_start "Set duplicates to dupAccept"
mylist.duplicates = "dupAccept"
prop=$(mylist.duplicates)
if [[ "$prop" == "dupAccept" ]]; then
    test_pass "duplicates set to 'dupAccept'"
else
    test_fail "duplicates is '$prop', expected 'dupAccept'"
fi

# Test: Get count property
test_start "Get count property"
mylist.Add "item1"
mylist.Add "item2"
count=$(mylist.count)
if [[ "$count" == "2" ]]; then
    test_pass "count property returns correct value"
else
    test_fail "count is '$count', expected '2'"
fi

# Test: Get capacity property
test_start "Get capacity property"
capacity=$(mylist.capacity)
if [[ "$capacity" -ge "2" ]]; then
    test_pass "capacity property returns valid value"
else
    test_fail "capacity is '$capacity', expected >= 2"
fi

# Test: Properties affect behavior - case sensitivity
test_start "case_sensitive property affects IndexOf"
TStringList.new caselist
caselist.case_sensitive = "false"
caselist.Add "Apple"
caselist.IndexOf "apple"
index1=$RESULT
caselist.case_sensitive = "true"
caselist.IndexOf "apple"
index2=$RESULT
if [[ "$index1" == "0" && "$index2" == "-1" ]]; then
    test_pass "case_sensitive property affects IndexOf behavior"
else
    test_fail "case_insensitive=$index1, case_sensitive=$index2"
fi
caselist.delete

# Test: Properties affect behavior - sorted/duplicates
test_start "sorted and duplicates properties affect Add"
TStringList.new proplist
proplist.sorted = "true"
proplist.duplicates = "dupIgnore"
proplist.Add "item"
proplist.Add "item"
index1=$RESULT
proplist.duplicates = "dupAccept"
proplist.sorted = "false"
proplist.Clear
proplist.Add "item"
proplist.Add "item"
count=$(proplist.count)
if [[ "$count" == "2" ]]; then
    test_pass "duplicates and sorted properties work correctly"
else
    test_fail "count is '$count', expected '2'"
fi
proplist.delete

# Test: Multiple property changes
test_start "Multiple rapid property changes"
TStringList.new multilist
for i in {1..5}; do
    multilist.case_sensitive = "true"
    multilist.sorted = "true"
    multilist.duplicates = "dupError"
    multilist.case_sensitive = "false"
    multilist.sorted = "false"
    multilist.duplicates = "dupAccept"
done
cs=$(multilist.case_sensitive)
s=$(multilist.sorted)
d=$(multilist.duplicates)
if [[ "$cs" == "false" && "$s" == "false" && "$d" == "dupAccept" ]]; then
    test_pass "Multiple property changes work correctly"
else
    test_fail "Final state: cs=$cs, s=$s, d=$d"
fi
multilist.delete

# Test: Properties are instance-specific
test_start "Properties are instance-specific"
TStringList.new list1
TStringList.new list2
list1.case_sensitive = "true"
list1.sorted = "true"
list2.case_sensitive = "false"
list2.sorted = "false"
cs1=$(list1.case_sensitive)
cs2=$(list2.case_sensitive)
s1=$(list1.sorted)
s2=$(list2.sorted)
if [[ "$cs1" == "true" && "$cs2" == "false" && "$s1" == "true" && "$s2" == "false" ]]; then
    test_pass "Properties are independent per instance"
else
    test_fail "Properties not independent: list1.cs=$cs1, list2.cs=$cs2"
fi
list1.delete
list2.delete

# Cleanup
mylist.delete

test_info "011_PropertyManipulation.sh completed"
