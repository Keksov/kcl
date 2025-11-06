#!/bin/bash
# 013_get_creation_time.sh - Test TFile.GetCreationTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=013
mkdir -p ".tmp/$TEST_ID"


# Test 1: Get creation time of existing file
test_start "Get creation time of existing file"
echo "content" > ".tmp/$TEST_ID/creation.tmp"
result=$(tfile.getCreationTime ".tmp/$TEST_ID/creation.tmp")
if [[ -n "$result" ]]; then
    test_pass "Get creation time of existing file"
else
    test_fail "Get creation time of existing file"
fi

# Test 2: Get creation time of non-existing file
test_start "Get creation time of non-existing file"
if ! result=$(tfile.getCreationTime ".tmp/$TEST_ID/nonexist.tmp" 2>&1); then
    test_pass "Get creation time of non-existing file (correctly failed)"
else
    test_fail "Get creation time of non-existing file (should have failed)"
fi

# Test 3: Get creation time of directory
test_start "Get creation time of directory"
mkdir -p ".tmp/$TEST_ID/creation_dir"
result=$(tfile.getCreationTime ".tmp/$TEST_ID/creation_dir")
if [[ -n "$result" ]]; then
    test_pass "Get creation time of directory"
else
    test_fail "Get creation time of directory"
fi
