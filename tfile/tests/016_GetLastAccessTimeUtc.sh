#!/bin/bash
# 016_get_last_access_time_utc.sh - Test TFile.GetLastAccessTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Get last access time UTC of existing file
test_start "Get last access time UTC of existing file"
echo "content" > test_access_utc.tmp
result=$(tfile.getLastAccessTimeUtc "test_access_utc.tmp")
if [[ -n "$result" ]]; then
    test_pass "Get last access time UTC of existing file"
else
    test_fail "Get last access time UTC of existing file"
fi

# Test 2: Get last access time UTC of non-existing file
test_start "Get last access time UTC of non-existing file"
if ! result=$(tfile.getLastAccessTimeUtc "nonexist.tmp" 2>&1); then
    test_pass "Get last access time UTC of non-existing file (correctly failed)"
else
    test_fail "Get last access time UTC of non-existing file (should have failed)"
fi
