#!/bin/bash
# 025_open_write.sh - Test TFile.OpenWrite method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Open existing file for write
test_start "Open existing file for write"
echo "old" > test_openwrite.tmp
stream=$(tfile.openWrite "test_openwrite.tmp")
if [[ -n "$stream" ]]; then
    test_pass "Open existing file for write"
    close_stream "$stream"
else
    test_fail "Open existing file for write"
fi

# Test 2: Open non-existing file for write
test_start "Open non-existing file for write"
rm -f test_openwrite_new.tmp
stream=$(tfile.openWrite "test_openwrite_new.tmp")
if [[ -f "test_openwrite_new.tmp" ]]; then
    test_pass "Open non-existing file for write"
    close_stream "$stream"
else
    test_fail "Open non-existing file for write"
fi
