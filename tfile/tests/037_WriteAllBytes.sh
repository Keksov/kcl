#!/bin/bash
# 037_write_all_bytes.sh - Test TFile.WriteAllBytes method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Write bytes to new file
test_start "Write bytes to new file"
bytes="Hello World"
result=$(tfile.writeAllBytes "test_writebytes.tmp" "$bytes")
if [[ -f "test_writebytes.tmp" && "$(cat test_writebytes.tmp)" == "$bytes" ]]; then
    test_pass "Write bytes to new file"
else
    test_fail "Write bytes to new file"
fi

# Test 2: Write bytes to existing file (overwrites)
test_start "Write bytes to existing file"
echo "old" > test_overwrite_bytes.tmp
result=$(tfile.writeAllBytes "test_overwrite_bytes.tmp" "new")
if [[ "$(cat test_overwrite_bytes.tmp)" == "new" ]]; then
    test_pass "Write bytes to existing file"
else
    test_fail "Write bytes to existing file"
fi

# Test 3: Write empty bytes
test_start "Write empty bytes"
result=$(tfile.writeAllBytes "test_empty_bytes.tmp" "")
if [[ -f "test_empty_bytes.tmp" && ! -s "test_empty_bytes.tmp" ]]; then
    test_pass "Write empty bytes"
else
    test_fail "Write empty bytes"
fi

# Test 4: Write to invalid path
test_start "Write bytes to invalid path"
if ! result=$(tfile.writeAllBytes "/invalid/path/file.tmp" "content" 2>&1); then
    test_pass "Write bytes to invalid path (correctly failed)"
else
    test_fail "Write bytes to invalid path (should have failed)"
fi
