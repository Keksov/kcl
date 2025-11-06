#!/bin/bash
# 035_set_last_write_time.sh - Test TFile.SetLastWriteTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=035
mkdir -p ".tmp/$TEST_ID"


# Test 1: Set last write time on existing file
test_start "Set last write time on existing file"
echo "content" > ".tmp/$TEST_ID/setwrite.tmp"
now=$(date +%s)
result=$(tfile.setLastWriteTime ".tmp/$TEST_ID/setwrite.tmp" "$now")
if [[ $? -eq 0 ]]; then
test_pass "Set last write time on existing file"
else
test_fail "Set last write time on existing file"
fi

# Test 2: Set last write time on non-existing file
test_start "Set last write time on non-existing file"
if ! result=$(tfile.setLastWriteTime ".tmp/$TEST_ID/nonexist.tmp" "$now" 2>&1); then
test_pass "Set last write time on non-existing file (correctly failed)"
else
test_fail "Set last write time on non-existing file (should have failed)"
fi
