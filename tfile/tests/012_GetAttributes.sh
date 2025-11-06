#!/bin/bash
# 012_get_attributes.sh - Test TFile.GetAttributes method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Get attributes of existing file
test_start "Get attributes of existing file"
echo "content" > test_attr.tmp
result=$(tfile.getAttributes "test_attr.tmp")
if [[ -n "$result" ]]; then
    test_pass "Get attributes of existing file"
else
    test_fail "Get attributes of existing file"
fi

# Test 2: Get attributes of non-existing file
test_start "Get attributes of non-existing file"
if ! result=$(tfile.getAttributes "nonexist.tmp" 2>&1); then
    test_pass "Get attributes of non-existing file (correctly failed)"
else
    test_fail "Get attributes of non-existing file (should have failed)"
fi

# Test 3: Get attributes with FollowLink=true
test_start "Get attributes with FollowLink=true"
echo "target" > test_attr_target.tmp
ln -s test_attr_target.tmp test_attr_link.tmp
result=$(tfile.getAttributes "test_attr_link.tmp" true)
if [[ -n "$result" ]]; then
    test_pass "Get attributes with FollowLink=true"
else
    test_fail "Get attributes with FollowLink=true"
fi

# Test 4: Get attributes of broken symlink with FollowLink=true
test_start "Get attributes of broken symlink with FollowLink=true"
ln -s nonexist.tmp test_attr_broken.tmp
if ! result=$(tfile.getAttributes "test_attr_broken.tmp" true 2>&1); then
    test_pass "Get attributes of broken symlink with FollowLink=true (correctly failed)"
else
    test_fail "Get attributes of broken symlink with FollowLink=true (should have failed)"
fi
