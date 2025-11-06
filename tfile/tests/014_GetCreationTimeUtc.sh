#!/bin/bash
# 014_get_creation_time_utc.sh - Test TFile.GetCreationTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Get creation time UTC of existing file
test_start "Get creation time UTC of existing file"
echo "content" > test_creation_utc.tmp
result=$(tfile.getCreationTimeUtc "test_creation_utc.tmp")
if [[ -n "$result" ]]; then
    test_pass "Get creation time UTC of existing file"
else
    test_fail "Get creation time UTC of existing file"
fi

# Test 2: Get creation time UTC of non-existing file
test_start "Get creation time UTC of non-existing file"
if ! result=$(tfile.getCreationTimeUtc "nonexist.tmp" 2>&1); then
    test_pass "Get creation time UTC of non-existing file (correctly failed)"
else
    test_fail "Get creation time UTC of non-existing file (should have failed)"
fi
