#!/bin/bash
# 022_open.sh - Test TFile.Open method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Open existing file for read
test_start "Open existing file for read"
echo "content" > test_open_read.tmp
stream=$(tfile.open "test_open_read.tmp" "fmOpenRead")
if [[ -n "$stream" ]]; then
    test_pass "Open existing file for read"
    close_stream "$stream"
else
    test_fail "Open existing file for read"
fi

# Test 2: Open for write (creates if not exists)
test_start "Open for write"
rm -f test_open_write.tmp
stream=$(tfile.open "test_open_write.tmp" "fmOpenWrite")
if [[ -f "test_open_write.tmp" ]]; then
    test_pass "Open for write"
    close_stream "$stream"
else
    test_fail "Open for write"
fi

# Test 3: Open with access and share
test_start "Open with access and share"
echo "content" > test_open_access.tmp
stream=$(tfile.open "test_open_access.tmp" "fmOpenReadWrite" "faReadWrite" "fsReadWrite")
if [[ -n "$stream" ]]; then
    test_pass "Open with access and share"
    close_stream "$stream"
else
    test_fail "Open with access and share"
fi

# Test 4: Open non-existing file for read
test_start "Open non-existing file for read"
if ! stream=$(tfile.open "nonexist.tmp" "fmOpenRead" 2>&1); then
    test_pass "Open non-existing file for read (correctly failed)"
else
    test_fail "Open non-existing file for read (should have failed)"
fi
