#!/bin/bash
# 023_open_read.sh - Test TFile.OpenRead method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=023
mkdir -p ".tmp/$TEST_ID"

# Test 1: Open existing file for read
test_start "Open existing file for read"
echo "content" > ".tmp/$TEST_ID/openread.tmp"
stream=$(tfile.openRead ".tmp/$TEST_ID/openread.tmp")
if [[ -n "$stream" ]]; then
    test_pass "Open existing file for read"
else
test_fail "Open existing file for read"
fi

# Test 2: Open non-existing file
test_start "Open non-existing file"
rm -f ".tmp/$TEST_ID/nonexistent.tmp"
if ! stream=$(tfile.openRead ".tmp/$TEST_ID/nonexistent.tmp" 2>&1); then
    test_pass "Open non-existing file (correctly failed)"
else
    test_fail "Open non-existing file (should have failed)"
fi
