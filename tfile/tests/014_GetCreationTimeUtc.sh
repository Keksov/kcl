#!/bin/bash
# 014_get_creation_time_utc.sh - Test TFile.GetCreationTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=014
mkdir -p ".tmp/$TEST_ID"


# Test 1: Get creation time UTC of existing file
test_start "Get creation time UTC of existing file"
echo "content" > ".tmp/$TEST_ID/creation_utc.tmp"
result=$(tfile.getCreationTimeUtc ".tmp/$TEST_ID/creation_utc.tmp")
if [[ -n "$result" ]]; then
    test_pass "Get creation time UTC of existing file"
else
    test_fail "Get creation time UTC of existing file"
fi

# Test 2: Get creation time UTC of non-existing file
test_start "Get creation time UTC of non-existing file"
if ! result=$(tfile.getCreationTimeUtc ".tmp/$TEST_ID/nonexist.tmp" 2>&1); then
    test_pass "Get creation time UTC of non-existing file (correctly failed)"
else
    test_fail "Get creation time UTC of non-existing file (should have failed)"
fi
