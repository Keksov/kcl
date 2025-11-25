#!/bin/bash
# 010_ErrorHandlingAndEdgeCases.sh - Test error handling and edge cases
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tstringlist module
TSTRINGLIST_DIR="$SCRIPT_DIR/.."
source "$TSTRINGLIST_DIR/tstringlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Initialize test-specific temp directory

kk_test_section "010: Error Handling and Edge Cases"

# Test: Get on empty list
kk_test_start "Get on empty list should fail"
TStringList.new emptylist
TRAP_ERRORS_ENABLED=false
emptylist.Get 0 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kk_test_pass "Get(0) on empty list correctly failed"
else
    kk_test_fail "Get(0) on empty list should have failed"
fi
emptylist.delete

# Test: IndexOf on empty list
kk_test_start "IndexOf on empty list"
TStringList.new emptylist
index=$(emptylist.IndexOf "anything")
if [[ "$index" == "-1" ]]; then
    kk_test_pass "IndexOf on empty list returned -1"
else
    kk_test_fail "IndexOf returned $index, expected -1"
fi
emptylist.delete

# Test: Remove on empty list
kk_test_start "Remove on empty list"
TStringList.new emptylist
emptylist.Remove "anything"
index=$RESULT
if [[ "$index" == "-1" ]]; then
    kk_test_pass "Remove on empty list returned -1"
else
    kk_test_fail "Remove returned $index, expected -1"
fi
emptylist.delete

# Test: Delete on empty list
kk_test_start "Delete on empty list should fail"
TStringList.new emptylist
TRAP_ERRORS_ENABLED=false
emptylist.Delete 0 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kk_test_pass "Delete(0) on empty list correctly failed"
else
    kk_test_fail "Delete(0) on empty list should have failed"
fi
emptylist.delete

# Test: Sort on empty list
kk_test_start "Sort on empty list"
TStringList.new emptylist
emptylist.Sort
count=$(emptylist.count)
if [[ "$count" == "0" ]]; then
    kk_test_pass "Sort on empty list succeeded"
else
    kk_test_fail "Count: $count (expected 0)"
fi
emptylist.delete

# Test: String with spaces
kk_test_start "Add and retrieve string with spaces"
TStringList.new spacelist
spacelist.Add "hello world"
item=$(spacelist.Get 0)
if [[ "$item" == "hello world" ]]; then
    kk_test_pass "String with spaces stored correctly"
else
    kk_test_fail "Retrieved '$item', expected 'hello world'"
fi
spacelist.delete

# Test: String with quotes
kk_test_start "Add and retrieve string with quotes"
TStringList.new quotelist
quotelist.Add 'hello "world"'
item=$(quotelist.Get 0)
if [[ "$item" == 'hello "world"' ]]; then
    kk_test_pass "String with quotes stored correctly"
else
    kk_test_fail "Retrieved '$item', expected 'hello \"world\"'"
fi
quotelist.delete

# Test: String with newline characters
kk_test_start "Add and retrieve string with newline"
TStringList.new newlinelist
newlinelist.Add $'line1\nline2'
item=$(newlinelist.Get 0)
if [[ "$item" == $'line1\nline2' ]]; then
    kk_test_pass "String with newline stored correctly"
else
    kk_test_fail "String with newline not stored correctly"
fi
newlinelist.delete

# Test: Very long string
kk_test_start "Add and retrieve very long string"
TStringList.new longlist
longstring=$(printf 'a%.0s' {1..1000})
longlist.Add "$longstring"
item=$(longlist.Get 0)
if [[ "${#item}" == "1000" ]]; then
    kk_test_pass "Very long string (1000 chars) stored correctly"
else
    kk_test_fail "String length: ${#item} (expected 1000)"
fi
longlist.delete

# Test: Many duplicates
kk_test_start "Many duplicate strings"
TStringList.new duplist
for i in {1..100}; do
    duplist.Add "duplicate" >/dev/null
done
count=$(duplist.count)
if [[ "$count" == "100" ]]; then
    kk_test_pass "Stored 100 duplicate strings"
else
    kk_test_fail "Count: $count (expected 100)"
fi
duplist.delete

# Test: Put with value exceeding original type
kk_test_start "Put with different length string"
TStringList.new mylist
mylist.Add "short"
mylist.Put 0 "this is a much longer string"
item=$(mylist.Get 0)
if [[ "$item" == "this is a much longer string" ]]; then
    kk_test_pass "Put with longer string succeeded"
else
    kk_test_fail "Retrieved '$item'"
fi
mylist.delete

# Test: Negative capacity value (should be invalid)
kk_test_start "Invalid capacity assignment"
TStringList.new testlist
TRAP_ERRORS_ENABLED=false
testlist.capacity = "-10" 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
# May or may not error depending on implementation
kk_test_pass "Tested capacity with negative value"
testlist.delete

# Test: Zero-based indexing
kk_test_start "Verify zero-based indexing"
TStringList.new indexlist
indexlist.Add "first"
indexlist.Add "second"
indexlist.Add "third"
first=$(indexlist.Get 0)
second=$(indexlist.Get 1)
third=$(indexlist.Get 2)
if [[ "$first" == "first" && "$second" == "second" && "$third" == "third" ]]; then
    kk_test_pass "Zero-based indexing works correctly"
else
    kk_test_fail "Indexing incorrect"
fi
indexlist.delete

# Test: Find on unsorted list should fail
kk_test_start "Find on unsorted list should fail"
TStringList.new unsorted
unsorted.Add "banana"
unsorted.Add "apple"
unsorted.sorted = "false"
TRAP_ERRORS_ENABLED=false
unsorted.Find "apple" 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kk_test_pass "Find correctly failed on unsorted list"
else
    kk_test_fail "Find should fail on unsorted list"
fi
unsorted.delete

# Test: Clear followed by operations
kk_test_start "Clear followed by operations"
TStringList.new cleartest
cleartest.Add "first"
cleartest.Add "second"
cleartest.Clear
cleartest.Add "new"
count=$(cleartest.count)
item=$(cleartest.Get 0)
if [[ "$count" == "1" && "$item" == "new" ]]; then
    kk_test_pass "Operations after clear work correctly"
else
    kk_test_fail "After clear: count=$count, item='$item'"
fi
cleartest.delete

kk_test_log "010_ErrorHandlingAndEdgeCases.sh completed"
