#!/bin/bash
# 004_create.sh - Test TFile.Create method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Create new file
test_start "Create new file"
rm -f test_create.tmp
stream=$(tfile.create "test_create.tmp")
if [[ -f "test_create.tmp" ]]; then
test_pass "Create new file"
# close_stream "$stream"
else
test_fail "Create new file"
fi

# Test 2: Create with buffer size
test_start "Create with buffer size"
rm -f test_create_buf.tmp
stream=$(tfile.create "test_create_buf.tmp" 8192)
if [[ -f "test_create_buf.tmp" ]]; then
test_pass "Create with buffer size"
# close_stream "$stream"
else
test_fail "Create with buffer size"
fi

# Test 3: Create existing file (should overwrite)
test_start "Create existing file"
printf "old" > test_overwrite.tmp
stream=$(tfile.create "test_overwrite.tmp")
if [[ -f "test_overwrite.tmp" && ! -s "test_overwrite.tmp" ]]; then
test_pass "Create existing file"
# close_stream "$stream"
else
test_fail "Create existing file"
fi

# Test 4: Create in invalid path
test_start "Create in invalid path"
if ! stream=$(tfile.create "/invalid/path/file.tmp" 2>&1); then
    test_pass "Create in invalid path (correctly failed)"
else
    test_fail "Create in invalid path (should have failed)"
fi
