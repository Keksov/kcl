#!/bin/bash
# 012_get_attributes.sh - Test TFile.GetAttributes method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=012
mkdir -p ".tmp/$TEST_ID"

# Check if symlinks are supported
if ln -s ".tmp/$TEST_ID/nonexist.tmp" ".tmp/$TEST_ID/test_link.tmp" 2>/dev/null; then
    SYMLINK_SUPPORTED=true
    rm -f ".tmp/$TEST_ID/test_link.tmp"
else
    SYMLINK_SUPPORTED=false
fi

# Test 1: Get attributes of existing file
test_start "Get attributes of existing file"
echo "content" > ".tmp/$TEST_ID/attr.tmp"
result=$(tfile.getAttributes ".tmp/$TEST_ID/attr.tmp")
if [[ -n "$result" ]]; then
    test_pass "Get attributes of existing file"
else
    test_fail "Get attributes of existing file"
fi

# Test 2: Get attributes of non-existing file
test_start "Get attributes of non-existing file"
if ! result=$(tfile.getAttributes ".tmp/$TEST_ID/nonexist.tmp" 2>&1); then
    test_pass "Get attributes of non-existing file (correctly failed)"
else
    test_fail "Get attributes of non-existing file (should have failed)"
fi

if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    # Test 3: Get attributes with FollowLink=true
    test_start "Get attributes with FollowLink=true"
    echo "target" > ".tmp/$TEST_ID/attr_target.tmp"
    ln -s ".tmp/$TEST_ID/attr_target.tmp" ".tmp/$TEST_ID/attr_link.tmp"
    result=$(tfile.getAttributes ".tmp/$TEST_ID/attr_link.tmp" true)
    if [[ -n "$result" ]]; then
        test_pass "Get attributes with FollowLink=true"
    else
        test_fail "Get attributes with FollowLink=true"
    fi

    # Test 4: Get attributes of broken symlink with FollowLink=true
    test_start "Get attributes of broken symlink with FollowLink=true"
    ln -s ".tmp/$TEST_ID/nonexist.tmp" ".tmp/$TEST_ID/attr_broken.tmp"
    if ! result=$(tfile.getAttributes ".tmp/$TEST_ID/attr_broken.tmp" true 2>&1); then
        test_pass "Get attributes of broken symlink with FollowLink=true (correctly failed)"
    else
        test_fail "Get attributes of broken symlink with FollowLink=true (should have failed)"
    fi
else
    test_pass "Get attributes with FollowLink=true (skipped: symlinks not supported)"
    test_pass "Get attributes of broken symlink with FollowLink=true (skipped: symlinks not supported)"
fi
