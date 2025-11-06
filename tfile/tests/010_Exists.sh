#!/bin/bash
# 010_exists.sh - Test TFile.Exists method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Check existing file
test_start "Check existing file"
echo "content" > test_exists.tmp
result=$(tfile.exists "test_exists.tmp")
if [[ $result == true ]]; then
    test_pass "Check existing file"
else
    test_fail "Check existing file"
fi

# Test 2: Check non-existing file
test_start "Check non-existing file"
result=$(tfile.exists "nonexist.tmp")
if [[ $result == false ]]; then
    test_pass "Check non-existing file"
else
    test_fail "Check non-existing file"
fi

# Test 3: Check directory
test_start "Check directory"
mkdir -p test_exists_dir
result=$(tfile.exists "test_exists_dir")
if [[ $result == false ]]; then
    test_pass "Check directory"
else
    test_fail "Check directory"
fi

# Test 4: Check symlink with FollowLink=true
test_start "Check symlink with FollowLink=true"
echo "target" > test_sym_target.tmp
ln -s test_sym_target.tmp test_sym_link.tmp
result=$(tfile.exists "test_sym_link.tmp" true)
if [[ $result == true ]]; then
    test_pass "Check symlink with FollowLink=true"
else
    test_fail "Check symlink with FollowLink=true"
fi

# Test 5: Check broken symlink with FollowLink=true
test_start "Check broken symlink with FollowLink=true"
ln -s nonexist.tmp test_broken_link.tmp
result=$(tfile.exists "test_broken_link.tmp" true)
if [[ $result == false ]]; then
    test_pass "Check broken symlink with FollowLink=true"
else
    test_fail "Check broken symlink with FollowLink=true"
fi

# Test 6: Check broken symlink with FollowLink=false
test_start "Check broken symlink with FollowLink=false"
result=$(tfile.exists "test_broken_link.tmp" false)
if [[ $result == true ]]; then
    test_pass "Check broken symlink with FollowLink=false"
else
    test_fail "Check broken symlink with FollowLink=false"
fi

# Test 7: Invalid path
test_start "Check invalid path"
result=$(tfile.exists "/invalid/path/file.tmp")
if [[ $result == false ]]; then
    test_pass "Check invalid path"
else
    test_fail "Check invalid path"
fi
