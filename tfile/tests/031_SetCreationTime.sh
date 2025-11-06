#!/bin/bash
# 031_set_creation_time.sh - Test TFile.SetCreationTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=031
mkdir -p ".tmp/$TEST_ID"

# Test 1: Set creation time on existing file
test_start "Set creation time on existing file"
echo "content" > ".tmp/$TEST_ID/setcreation.tmp"
now=$(date +%s)
result=$(tfile.setCreationTime ".tmp/$TEST_ID/setcreation.tmp" "$now")
if [[ $? -eq 0 ]]; then
    test_pass "Set creation time on existing file"
else
    test_fail "Set creation time on existing file"
fi

# Test 2: Set creation time on non-existing file
test_start "Set creation time on non-existing file"
if ! result=$(tfile.setCreationTime ".tmp/$TEST_ID/nonexist.tmp" "$now" 2>&1); then
    test_pass "Set creation time on non-existing file (correctly failed)"
else
    test_fail "Set creation time on non-existing file (should have failed)"
fi
