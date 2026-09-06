#!/bin/bash
# 010_ErrorHandlingAndEdgeCases.sh - Test error handling and edge cases
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tstringlist module
TSTRINGLIST_DIR="$SCRIPT_DIR/.."
source "$TSTRINGLIST_DIR/tstringlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Initialize test-specific temp directory

kt_test_section "010: Error Handling and Edge Cases"

# Test: Get on empty list
kt_test_start "Get on empty list should fail"
TStringList.new emptylist
TRAP_ERRORS_ENABLED=false
emptylist.Get 0 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kt_test_pass "Get(0) on empty list correctly failed"
else
    kt_test_fail "Get(0) on empty list should have failed"
fi
emptylist.delete

# Test: IndexOf on empty list
kt_test_start "IndexOf on empty list"
TStringList.new emptylist
index=$(emptylist.IndexOf "anything")
if [[ "$index" == "-1" ]]; then
    kt_test_pass "IndexOf on empty list returned -1"
else
    kt_test_fail "IndexOf returned $index, expected -1"
fi
emptylist.delete

# Test: Remove on empty list
kt_test_start "Remove on empty list"
TStringList.new emptylist
emptylist.Remove "anything"
index=$RESULT
if [[ "$index" == "-1" ]]; then
    kt_test_pass "Remove on empty list returned -1"
else
    kt_test_fail "Remove returned $index, expected -1"
fi
emptylist.delete

# Test: Delete on empty list
kt_test_start "Delete on empty list should fail"
TStringList.new emptylist
TRAP_ERRORS_ENABLED=false
emptylist.Delete 0 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kt_test_pass "Delete(0) on empty list correctly failed"
else
    kt_test_fail "Delete(0) on empty list should have failed"
fi
emptylist.delete

# Test: Sort on empty list
kt_test_start "Sort on empty list"
TStringList.new emptylist
emptylist.Sort
count=$(emptylist.count)
if [[ "$count" == "0" ]]; then
    kt_test_pass "Sort on empty list succeeded"
else
    kt_test_fail "Count: $count (expected 0)"
fi
emptylist.delete

# Test: String with spaces
kt_test_start "Add and retrieve string with spaces"
TStringList.new spacelist
spacelist.Add "hello world"
item=$(spacelist.Get 0)
if [[ "$item" == "hello world" ]]; then
    kt_test_pass "String with spaces stored correctly"
else
    kt_test_fail "Retrieved '$item', expected 'hello world'"
fi
spacelist.delete

# Test: String with quotes
kt_test_start "Add and retrieve string with quotes"
TStringList.new quotelist
quotelist.Add 'hello "world"'
item=$(quotelist.Get 0)
if [[ "$item" == 'hello "world"' ]]; then
    kt_test_pass "String with quotes stored correctly"
else
    kt_test_fail "Retrieved '$item', expected 'hello \"world\"'"
fi
quotelist.delete

# Test: String with newline characters
kt_test_start "Add and retrieve string with newline"
TStringList.new newlinelist
newlinelist.Add $'line1\nline2'
item=$(newlinelist.Get 0)
if [[ "$item" == $'line1\nline2' ]]; then
    kt_test_pass "String with newline stored correctly"
else
    kt_test_fail "String with newline not stored correctly"
fi
newlinelist.delete

# Test: Very long string
kt_test_start "Add and retrieve very long string"
TStringList.new longlist
longstring=$(printf 'a%.0s' {1..1000})
longlist.Add "$longstring"
item=$(longlist.Get 0)
if [[ "${#item}" == "1000" ]]; then
    kt_test_pass "Very long string (1000 chars) stored correctly"
else
    kt_test_fail "String length: ${#item} (expected 1000)"
fi
longlist.delete

# Test: Many duplicates
kt_test_start "Many duplicate strings"
TStringList.new duplist
for i in {1..100}; do
    duplist.Add "duplicate" >/dev/null
done
count=$(duplist.count)
if [[ "$count" == "100" ]]; then
    kt_test_pass "Stored 100 duplicate strings"
else
    kt_test_fail "Count: $count (expected 100)"
fi
duplist.delete

# Test: Put with value exceeding original type
kt_test_start "Put with different length string"
TStringList.new mylist
mylist.Add "short"
mylist.Put 0 "this is a much longer string"
item=$(mylist.Get 0)
if [[ "$item" == "this is a much longer string" ]]; then
    kt_test_pass "Put with longer string succeeded"
else
    kt_test_fail "Retrieved '$item'"
fi
mylist.delete

# Test: Negative capacity value (invalid).
# REWRITTEN for the 2026-09-06 review: this used to call kt_test_pass
# unconditionally, so it could not fail. FPC SetCapacity raises
# EListError (SListCapacityError) below Count or below zero; decision R2 maps
# that to rc 1 with the list left exactly as it was (finding G1-09).
kt_test_start "Invalid capacity assignment is refused and changes nothing"
TStringList.new testlist
testlist.Add "one"
testlist.Add "two"
cap_before=$(testlist.capacity)
TRAP_ERRORS_ENABLED=false
testlist.capacity = "-10" 2>/dev/null
neg_rc=$?
testlist.capacity = "1" 2>/dev/null
low_rc=$?
TRAP_ERRORS_ENABLED=true
count_after=$(testlist.count)
cap_after=$(testlist.capacity)
item0=$(testlist.Get 0)
item1=$(testlist.Get 1)
if [[ $neg_rc -eq 1 && $low_rc -eq 1 && "$count_after" == "2" \
   && "$cap_after" == "$cap_before" && "$item0" == "one" && "$item1" == "two" ]]; then
    kt_test_pass "negative and below-count capacity both rc 1, list intact"
else
    kt_test_fail "neg_rc=$neg_rc low_rc=$low_rc count=$count_after capacity=$cap_after (was $cap_before) items='$item0','$item1'"
fi
testlist.delete

# Test: Zero-based indexing
kt_test_start "Verify zero-based indexing"
TStringList.new indexlist
indexlist.Add "first"
indexlist.Add "second"
indexlist.Add "third"
first=$(indexlist.Get 0)
second=$(indexlist.Get 1)
third=$(indexlist.Get 2)
if [[ "$first" == "first" && "$second" == "second" && "$third" == "third" ]]; then
    kt_test_pass "Zero-based indexing works correctly"
else
    kt_test_fail "Indexing incorrect"
fi
indexlist.delete

# Test: Find on unsorted list should fail
kt_test_start "Find on unsorted list should fail"
TStringList.new unsorted
unsorted.Add "banana"
unsorted.Add "apple"
unsorted.sorted = "false"
TRAP_ERRORS_ENABLED=false
unsorted.Find "apple" 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kt_test_pass "Find correctly failed on unsorted list"
else
    kt_test_fail "Find should fail on unsorted list"
fi
unsorted.delete

# Test: Clear followed by operations
kt_test_start "Clear followed by operations"
TStringList.new cleartest
cleartest.Add "first"
cleartest.Add "second"
cleartest.Clear
cleartest.Add "new"
count=$(cleartest.count)
item=$(cleartest.Get 0)
if [[ "$count" == "1" && "$item" == "new" ]]; then
    kt_test_pass "Operations after clear work correctly"
else
    kt_test_fail "After clear: count=$count, item='$item'"
fi
cleartest.delete

kt_test_log "010_ErrorHandlingAndEdgeCases.sh completed"
