#!/bin/bash
# 008_Index_Of_Operations.sh - Test Index Of Operations
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

kk_test_section "008: Index Of Operations"

# Create TList instance and populate
TList.new testlist
testlist.Add "apple"
testlist.Add "banana"
testlist.Add "cherry"
testlist.Add "apple"  # duplicate

# Test: IndexOf existing item (first occurrence)
kk_test_start "IndexOf existing item"
testlist.IndexOf "banana"
index="$RESULT"
if [[ "$index" == "1" ]]; then
    kk_test_pass "IndexOf found banana at index $index"
else
    kk_test_fail "IndexOf failed for banana: got $index, expected 1"
fi

# Test: IndexOf first item
kk_test_start "IndexOf first item"
testlist.IndexOf "apple"
index="$RESULT"
if [[ "$index" == "0" ]]; then
    kk_test_pass "IndexOf found first apple at index $index"
else
    kk_test_fail "IndexOf failed for first apple: got $index, expected 0"
fi

# Test: IndexOf last item
kk_test_start "IndexOf last item"
testlist.IndexOf "cherry"
index="$RESULT"
if [[ "$index" == "2" ]]; then
    kk_test_pass "IndexOf found cherry at index $index"
else
    kk_test_fail "IndexOf failed for cherry: got $index, expected 2"
fi

# Test: IndexOf non-existing item
kk_test_start "IndexOf non-existing item"
testlist.IndexOf "grape"
index="$RESULT"
if [[ "$index" == "-1" ]]; then
    kk_test_pass "IndexOf correctly returned -1 for non-existing item"
else
    kk_test_fail "IndexOf failed for non-existing: got $index, expected -1"
fi

# Test: IndexOf empty string
kk_test_start "IndexOf empty string"
testlist.Add ""
testlist.IndexOf ""
index="$RESULT"
if [[ "$index" == "4" ]]; then
    kk_test_pass "IndexOf found empty string at index $index"
else
    kk_test_fail "IndexOf failed for empty string: got $index, expected 4"
fi

# Test: IndexOf in empty list
kk_test_start "IndexOf in empty list"
TList.new emptylist
emptylist.IndexOf "anything"
index="$RESULT"
if [[ "$index" == "-1" ]]; then
    kk_test_pass "IndexOf correctly returned -1 for empty list"
else
    kk_test_fail "IndexOf failed for empty list: got $index, expected -1"
fi
emptylist.delete

# Cleanup
testlist.delete

kk_test_log "008_Index_Of_Operations.sh completed"
