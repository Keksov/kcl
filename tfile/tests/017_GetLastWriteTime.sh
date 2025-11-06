#!/bin/bash
# 017_get_last_write_time.sh - Test TFile.GetLastWriteTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=017
mkdir -p ".tmp/$TEST_ID"


# Test 1: Get last write time of existing file
test_start "Get last write time of existing file"
echo "content" > ".tmp/$TEST_ID/write.tmp"
result=$(tfile.getLastWriteTime ".tmp/$TEST_ID/write.tmp")
if [[ -n "$result" ]]; then
    test_pass "Get last write time of existing file"
else
    test_fail "Get last write time of existing file"
fi

# Test 2: Get last write time of non-existing file
test_start "Get last write time of non-existing file"
if ! result=$(tfile.getLastWriteTime ".tmp/$TEST_ID/nonexist.tmp" 2>&1); then
    test_pass "Get last write time of non-existing file (correctly failed)"
else
    test_fail "Get last write time of non-existing file (should have failed)"
fi
