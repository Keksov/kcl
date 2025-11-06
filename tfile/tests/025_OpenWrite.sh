#!/bin/bash
# 025_open_write.sh - Test TFile.OpenWrite method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=025
mkdir -p ".tmp/$TEST_ID"

# Test 1: Open existing file for write
test_start "Open existing file for write"
echo "old" > ".tmp/$TEST_ID/openwrite.tmp"
stream=$(tfile.openWrite ".tmp/$TEST_ID/openwrite.tmp")
if [[ -n "$stream" ]]; then
    test_pass "Open existing file for write"
else
test_fail "Open existing file for write"
fi

# Test 2: Open non-existing file for write
test_start "Open non-existing file for write"
stream=$(tfile.openWrite ".tmp/$TEST_ID/openwrite_new.tmp")
if [[ -f ".tmp/$TEST_ID/openwrite_new.tmp" ]]; then
    test_pass "Open non-existing file for write"
else
    test_fail "Open non-existing file for write"
fi
