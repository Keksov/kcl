#!/bin/bash
# 010_exists.sh - Test TFile.Exists method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=010
mkdir -p ".tmp/$TEST_ID"

# Check if symlinks are supported
if ln -s ".tmp/$TEST_ID/nonexist.tmp" ".tmp/$TEST_ID/test_link.tmp" 2>/dev/null; then
    SYMLINK_SUPPORTED=true
    rm -f ".tmp/$TEST_ID/test_link.tmp"
else
    SYMLINK_SUPPORTED=false
fi

# Test 1: Check existing file
test_start "Check existing file"
echo "content" > ".tmp/$TEST_ID/exists.tmp"
result=$(tfile.exists ".tmp/$TEST_ID/exists.tmp")
if [[ $result == true ]]; then
    test_pass "Check existing file"
else
    test_fail "Check existing file"
fi

# Test 2: Check non-existing file
test_start "Check non-existing file"
result=$(tfile.exists ".tmp/$TEST_ID/nonexist.tmp")
if [[ $result == false ]]; then
    test_pass "Check non-existing file"
else
    test_fail "Check non-existing file"
fi

# Test 3: Check directory
test_start "Check directory"
mkdir -p ".tmp/$TEST_ID/exists_dir"
result=$(tfile.exists ".tmp/$TEST_ID/exists_dir")
if [[ $result == false ]]; then
    test_pass "Check directory"
else
    test_fail "Check directory"
fi

# Test 4: Check symlink with FollowLink=true
test_start "Check symlink with FollowLink=true"
if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    echo "target" > ".tmp/$TEST_ID/sym_target.tmp"
    ln -s ".tmp/$TEST_ID/sym_target.tmp" ".tmp/$TEST_ID/sym_link.tmp"
    result=$(tfile.exists ".tmp/$TEST_ID/sym_link.tmp" true)
if [[ $result == true ]]; then
        test_pass "Check symlink with FollowLink=true"
else
        test_fail "Check symlink with FollowLink=true"
    fi
else
    test_pass "Check symlink with FollowLink=true (skipped: symlinks not supported)"
fi

# Test 5: Check broken symlink with FollowLink=true
test_start "Check broken symlink with FollowLink=true"
if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
ln -s ".tmp/$TEST_ID/nonexist.tmp" ".tmp/$TEST_ID/broken_link.tmp"
    result=$(tfile.exists ".tmp/$TEST_ID/broken_link.tmp" true)
    if [[ $result == false ]]; then
        test_pass "Check broken symlink with FollowLink=true"
    else
        test_fail "Check broken symlink with FollowLink=true"
    fi
else
    test_pass "Check broken symlink with FollowLink=true (skipped: symlinks not supported)"
fi

# Test 6: Check broken symlink with FollowLink=false
test_start "Check broken symlink with FollowLink=false"
if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    result=$(tfile.exists ".tmp/$TEST_ID/broken_link.tmp" false)
    if [[ $result == true ]]; then
        test_pass "Check broken symlink with FollowLink=false"
    else
        test_fail "Check broken symlink with FollowLink=false"
    fi
else
    test_pass "Check broken symlink with FollowLink=false (skipped: symlinks not supported)"
fi

# Test 7: Invalid path
test_start "Check invalid path"
result=$(tfile.exists "/invalid/path/file.tmp")
if [[ $result == false ]]; then
    test_pass "Check invalid path"
else
    test_fail "Check invalid path"
fi
