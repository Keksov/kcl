#!/bin/bash
# 010_exists.sh - Test TFile.Exists method
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

# Test 1: Check existing file
kt_test_start "Check existing file"
echo "content" > "$_KT_TMPDIR/exists.tmp"
result=$(tfile.exists "$_KT_TMPDIR/exists.tmp")
if [[ $result == true ]]; then
    kt_test_pass "Check existing file"
else
    kt_test_fail "Check existing file"
fi

# Test 2: Check non-existing file
kt_test_start "Check non-existing file"
result=$(tfile.exists "$_KT_TMPDIR/nonexist.tmp")
if [[ $result == false ]]; then
    kt_test_pass "Check non-existing file"
else
    kt_test_fail "Check non-existing file"
fi

# Test 3: Check directory
kt_test_start "Check directory"
mkdir -p "$_KT_TMPDIR/exists_dir"
result=$(tfile.exists "$_KT_TMPDIR/exists_dir")
if [[ $result == false ]]; then
    kt_test_pass "Check directory"
else
    kt_test_fail "Check directory"
fi

# Test 4: Check symlink with FollowLink=true
kt_test_start "Check symlink with FollowLink=true"
if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    echo "target" > "$_KT_TMPDIR/sym_target.tmp"
    ln -s "$_KT_TMPDIR/sym_target.tmp" "$_KT_TMPDIR/sym_link.tmp"
    result=$(tfile.exists "$_KT_TMPDIR/sym_link.tmp" true)
if [[ $result == true ]]; then
        kt_test_pass "Check symlink with FollowLink=true"
else
        kt_test_fail "Check symlink with FollowLink=true"
    fi
else
    kt_test_pass "Check symlink with FollowLink=true (skipped: symlinks not supported)"
fi

# Test 5: Check broken symlink with FollowLink=true
kt_test_start "Check broken symlink with FollowLink=true"
if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
ln -s "$_KT_TMPDIR/nonexist.tmp" "$_KT_TMPDIR/broken_link.tmp"
    result=$(tfile.exists "$_KT_TMPDIR/broken_link.tmp" true)
    if [[ $result == false ]]; then
        kt_test_pass "Check broken symlink with FollowLink=true"
    else
        kt_test_fail "Check broken symlink with FollowLink=true"
    fi
else
    kt_test_pass "Check broken symlink with FollowLink=true (skipped: symlinks not supported)"
fi

# Test 6: Check broken symlink with FollowLink=false
kt_test_start "Check broken symlink with FollowLink=false"
if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    result=$(tfile.exists "$_KT_TMPDIR/broken_link.tmp" false)
    if [[ $result == true ]]; then
        kt_test_pass "Check broken symlink with FollowLink=false"
    else
        kt_test_fail "Check broken symlink with FollowLink=false"
    fi
else
    kt_test_pass "Check broken symlink with FollowLink=false (skipped: symlinks not supported)"
fi

# Test 7: Invalid path
kt_test_start "Check invalid path"
result=$(tfile.exists "/invalid/path/file.tmp")
if [[ $result == false ]]; then
    kt_test_pass "Check invalid path"
else
    kt_test_fail "Check invalid path"
fi
