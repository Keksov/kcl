#!/bin/bash
# 033_set_last_access_time.sh - Test TFile.SetLastAccessTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Set last access time on existing file
test_start "Set last access time on existing file"
echo "content" > test_setaccess.tmp
now=$(date +%s)
result=$(tfile.setLastAccessTime "test_setaccess.tmp" "$now")
if [[ $? -eq 0 ]]; then
    test_pass "Set last access time on existing file"
else
    test_fail "Set last access time on existing file"
fi

# Test 2: Set last access time on non-existing file
test_start "Set last access time on non-existing file"
if ! result=$(tfile.setLastAccessTime "nonexist.tmp" "$now" 2>&1); then
    test_pass "Set last access time on non-existing file (correctly failed)"
else
    test_fail "Set last access time on non-existing file (should have failed)"
fi
