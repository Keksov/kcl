#!/bin/bash
# 031_set_creation_time.sh - Test TFile.SetCreationTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Set creation time on existing file
test_start "Set creation time on existing file"
echo "content" > test_setcreation.tmp
now=$(date +%s)
result=$(tfile.setCreationTime "test_setcreation.tmp" "$now")
if [[ $? -eq 0 ]]; then
    test_pass "Set creation time on existing file"
else
    test_fail "Set creation time on existing file"
fi

# Test 2: Set creation time on non-existing file
test_start "Set creation time on non-existing file"
if ! result=$(tfile.setCreationTime "nonexist.tmp" "$now" 2>&1); then
    test_pass "Set creation time on non-existing file (correctly failed)"
else
    test_fail "Set creation time on non-existing file (should have failed)"
fi
