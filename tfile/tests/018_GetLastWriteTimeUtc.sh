#!/bin/bash
# 018_get_last_write_time_utc.sh - Test TFile.GetLastWriteTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=018
mkdir -p ".tmp/$TEST_ID"


# Test 1: Get last write time UTC of existing file
test_start "Get last write time UTC of existing file"
echo "content" > ".tmp/$TEST_ID/write_utc.tmp"
result=$(tfile.getLastWriteTimeUtc ".tmp/$TEST_ID/write_utc.tmp")
if [[ -n "$result" ]]; then
    test_pass "Get last write time UTC of existing file"
else
    test_fail "Get last write time UTC of existing file"
fi

# Test 2: Get last write time UTC of non-existing file
test_start "Get last write time UTC of non-existing file"
if ! result=$(tfile.getLastWriteTimeUtc ".tmp/$TEST_ID/nonexist.tmp" 2>&1); then
    test_pass "Get last write time UTC of non-existing file (correctly failed)"
else
    test_fail "Get last write time UTC of non-existing file (should have failed)"
fi
