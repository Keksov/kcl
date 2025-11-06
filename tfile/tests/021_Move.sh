#!/bin/bash
# 021_move.sh - Test TFile.Move method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=021
mkdir -p ".tmp/$TEST_ID"

# Test 1: Move existing file
test_start "Move existing file"
echo "content" > ".tmp/$TEST_ID/move_source.tmp"
result=$(tfile.move ".tmp/$TEST_ID/move_source.tmp" ".tmp/$TEST_ID/move_dest.tmp")
if [[ ! -f ".tmp/$TEST_ID/move_source.tmp" && -f ".tmp/$TEST_ID/move_dest.tmp" && "$(cat .tmp/$TEST_ID/move_dest.tmp)" == "content" ]]; then
    test_pass "Move existing file"
else
    test_fail "Move existing file"
fi

# Test 2: Move to existing destination
test_start "Move to existing destination"
echo "source2" > ".tmp/$TEST_ID/move_source2.tmp"
echo "dest2" > ".tmp/$TEST_ID/move_dest2.tmp"
if ! result=$(tfile.move ".tmp/$TEST_ID/move_source2.tmp" ".tmp/$TEST_ID/move_dest2.tmp" 2>&1); then
    test_pass "Move to existing destination (correctly failed)"
else
    test_fail "Move to existing destination (should have failed)"
fi

# Test 3: Move non-existing source
test_start "Move non-existing source"
if ! result=$(tfile.move ".tmp/$TEST_ID/nonexist.tmp" ".tmp/$TEST_ID/dest.tmp" 2>&1); then
    test_pass "Move non-existing source (correctly failed)"
else
    test_fail "Move non-existing source (should have failed)"
fi

# Test 4: Move to invalid path
test_start "Move to invalid path"
echo "source3" > ".tmp/$TEST_ID/move_source3.tmp"
if ! result=$(tfile.move ".tmp/$TEST_ID/move_source3.tmp" "/invalid/path/file.tmp" 2>&1); then
    test_pass "Move to invalid path (correctly failed)"
else
    test_fail "Move to invalid path (should have failed)"
fi
