#!/bin/bash
# 032_set_creation_time_utc.sh - Test TFile.SetCreationTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Set creation time UTC on existing file
test_start "Set creation time UTC on existing file"
echo "content" > test_setcreation_utc.tmp
now=$(date +%s)
result=$(tfile.setCreationTimeUtc "test_setcreation_utc.tmp" "$now")
if [[ $? -eq 0 ]]; then
    test_pass "Set creation time UTC on existing file"
else
    test_fail "Set creation time UTC on existing file"
fi

# Test 2: Set creation time UTC on non-existing file
test_start "Set creation time UTC on non-existing file"
if ! result=$(tfile.setCreationTimeUtc "nonexist.tmp" "$now" 2>&1); then
    test_pass "Set creation time UTC on non-existing file (correctly failed)"
else
    test_fail "Set creation time UTC on non-existing file (should have failed)"
fi
