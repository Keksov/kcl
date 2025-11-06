#!/bin/bash
# 034_set_last_access_time_utc.sh - Test TFile.SetLastAccessTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=034
mkdir -p ".tmp/$TEST_ID"


# Test 1: Set last access time UTC on existing file
test_start "Set last access time UTC on existing file"
echo "content" > ".tmp/$TEST_ID/setaccess_utc.tmp"
now=$(date +%s)
result=$(tfile.setLastAccessTimeUtc ".tmp/$TEST_ID/setaccess_utc.tmp" "$now")
if [[ $? -eq 0 ]]; then
test_pass "Set last access time UTC on existing file"
else
test_fail "Set last access time UTC on existing file"
fi

# Test 2: Set last access time UTC on non-existing file
test_start "Set last access time UTC on non-existing file"
if ! result=$(tfile.setLastAccessTimeUtc ".tmp/$TEST_ID/nonexist.tmp" "$now" 2>&1); then
test_pass "Set last access time UTC on non-existing file (correctly failed)"
else
test_fail "Set last access time UTC on non-existing file (should have failed)"
fi
