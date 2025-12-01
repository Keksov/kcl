#!/bin/bash
# 012_get_attributes.sh - Test TFile.GetAttributes method
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Set up temp directory for this test

# Check if symlinks are supported
if ln -s "$_KT_TMPDIR/nonexist.tmp" "$_KT_TMPDIR/test_link.tmp" 2>/dev/null; then
    SYMLINK_SUPPORTED=true
    rm -f "$_KT_TMPDIR/test_link.tmp"
else
    SYMLINK_SUPPORTED=false
fi

# Test 1: Get attributes of existing file
kt_test_start "Get attributes of existing file"
echo "content" > "$_KT_TMPDIR/attr.tmp"
result=$(tfile.getAttributes "$_KT_TMPDIR/attr.tmp")
if [[ -n "$result" ]]; then
    kt_test_pass "Get attributes of existing file"
else
    kt_test_fail "Get attributes of existing file"
fi

# Test 2: Get attributes of non-existing file
kt_test_start "Get attributes of non-existing file"
if ! result=$(tfile.getAttributes "$_KT_TMPDIR/nonexist.tmp" 2>&1); then
    kt_test_pass "Get attributes of non-existing file (correctly failed)"
else
    kt_test_fail "Get attributes of non-existing file (should have failed)"
fi

if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    # Test 3: Get attributes with FollowLink=true
    kt_test_start "Get attributes with FollowLink=true"
    echo "target" > "$_KT_TMPDIR/attr_target.tmp"
    ln -s "$_KT_TMPDIR/attr_target.tmp" "$_KT_TMPDIR/attr_link.tmp"
    result=$(tfile.getAttributes "$_KT_TMPDIR/attr_link.tmp" true)
    if [[ -n "$result" ]]; then
        kt_test_pass "Get attributes with FollowLink=true"
    else
        kt_test_fail "Get attributes with FollowLink=true"
    fi

    # Test 4: Get attributes of broken symlink with FollowLink=true
    kt_test_start "Get attributes of broken symlink with FollowLink=true"
    ln -s "$_KT_TMPDIR/nonexist.tmp" "$_KT_TMPDIR/attr_broken.tmp"
    if ! result=$(tfile.getAttributes "$_KT_TMPDIR/attr_broken.tmp" true 2>&1); then
        kt_test_pass "Get attributes of broken symlink with FollowLink=true (correctly failed)"
    else
        kt_test_fail "Get attributes of broken symlink with FollowLink=true (should have failed)"
    fi
else
    kt_test_pass "Get attributes with FollowLink=true (skipped: symlinks not supported)"
    kt_test_pass "Get attributes of broken symlink with FollowLink=true (skipped: symlinks not supported)"
fi
