#!/bin/bash
# 008_delete.sh - Test TFile.Delete method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=008
mkdir -p ".tmp/$TEST_ID"

# Test 1: Delete existing file
test_start "Delete existing file"
echo "content" > ".tmp/$TEST_ID/delete.tmp"
result=$(tfile.delete ".tmp/$TEST_ID/delete.tmp")
if [[ ! -f ".tmp/$TEST_ID/delete.tmp" ]]; then
    test_pass "Delete existing file"
else
    test_fail "Delete existing file"
fi

# Test 2: Delete non-existing file
test_start "Delete non-existing file"
if ! result=$(tfile.delete ".tmp/$TEST_ID/nonexist.tmp" 2>&1); then
    test_pass "Delete non-existing file (correctly failed)"
else
    test_fail "Delete non-existing file (should have failed)"
fi

# Test 3: Delete directory (should fail)
test_start "Delete directory"
mkdir -p ".tmp/$TEST_ID/delete_dir"
if ! result=$(tfile.delete ".tmp/$TEST_ID/delete_dir" 2>&1); then
    test_pass "Delete directory (correctly failed)"
else
    test_fail "Delete directory (should have failed)"
fi

# Test 4: Delete with invalid path
test_start "Delete with invalid path"
if ! result=$(tfile.delete "/invalid/path/file.tmp" 2>&1); then
    test_pass "Delete with invalid path (correctly failed)"
else
    test_fail "Delete with invalid path (should have failed)"
fi
