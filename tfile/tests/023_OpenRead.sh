#!/bin/bash
# 023_open_read.sh - Test TFile.OpenRead method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Open existing file for read
test_start "Open existing file for read"
echo "content" > test_openread.tmp
stream=$(tfile.openRead "test_openread.tmp")
if [[ -n "$stream" ]]; then
    test_pass "Open existing file for read"
    close_stream "$stream"
else
    test_fail "Open existing file for read"
fi

# Test 2: Open non-existing file
test_start "Open non-existing file"
if ! stream=$(tfile.openRead "nonexist.tmp" 2>&1); then
    test_pass "Open non-existing file (correctly failed)"
else
    test_fail "Open non-existing file (should have failed)"
fi
