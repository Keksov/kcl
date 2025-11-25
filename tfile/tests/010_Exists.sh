#!/bin/bash
# 010_exists.sh - Test TFile.Exists method
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Set up temp directory for this test

# Check if symlinks are supported
if ln -s "$KK_TEST_TMPDIR/nonexist.tmp" "$KK_TEST_TMPDIR/test_link.tmp" 2>/dev/null; then
    SYMLINK_SUPPORTED=true
    rm -f "$KK_TEST_TMPDIR/test_link.tmp"
else
    SYMLINK_SUPPORTED=false
fi

# Test 1: Check existing file
kk_test_start "Check existing file"
echo "content" > "$KK_TEST_TMPDIR/exists.tmp"
result=$(tfile.exists "$KK_TEST_TMPDIR/exists.tmp")
if [[ $result == true ]]; then
    kk_test_pass "Check existing file"
else
    kk_test_fail "Check existing file"
fi

# Test 2: Check non-existing file
kk_test_start "Check non-existing file"
result=$(tfile.exists "$KK_TEST_TMPDIR/nonexist.tmp")
if [[ $result == false ]]; then
    kk_test_pass "Check non-existing file"
else
    kk_test_fail "Check non-existing file"
fi

# Test 3: Check directory
kk_test_start "Check directory"
mkdir -p "$KK_TEST_TMPDIR/exists_dir"
result=$(tfile.exists "$KK_TEST_TMPDIR/exists_dir")
if [[ $result == false ]]; then
    kk_test_pass "Check directory"
else
    kk_test_fail "Check directory"
fi

# Test 4: Check symlink with FollowLink=true
kk_test_start "Check symlink with FollowLink=true"
if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    echo "target" > "$KK_TEST_TMPDIR/sym_target.tmp"
    ln -s "$KK_TEST_TMPDIR/sym_target.tmp" "$KK_TEST_TMPDIR/sym_link.tmp"
    result=$(tfile.exists "$KK_TEST_TMPDIR/sym_link.tmp" true)
if [[ $result == true ]]; then
        kk_test_pass "Check symlink with FollowLink=true"
else
        kk_test_fail "Check symlink with FollowLink=true"
    fi
else
    kk_test_pass "Check symlink with FollowLink=true (skipped: symlinks not supported)"
fi

# Test 5: Check broken symlink with FollowLink=true
kk_test_start "Check broken symlink with FollowLink=true"
if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
ln -s "$KK_TEST_TMPDIR/nonexist.tmp" "$KK_TEST_TMPDIR/broken_link.tmp"
    result=$(tfile.exists "$KK_TEST_TMPDIR/broken_link.tmp" true)
    if [[ $result == false ]]; then
        kk_test_pass "Check broken symlink with FollowLink=true"
    else
        kk_test_fail "Check broken symlink with FollowLink=true"
    fi
else
    kk_test_pass "Check broken symlink with FollowLink=true (skipped: symlinks not supported)"
fi

# Test 6: Check broken symlink with FollowLink=false
kk_test_start "Check broken symlink with FollowLink=false"
if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    result=$(tfile.exists "$KK_TEST_TMPDIR/broken_link.tmp" false)
    if [[ $result == true ]]; then
        kk_test_pass "Check broken symlink with FollowLink=false"
    else
        kk_test_fail "Check broken symlink with FollowLink=false"
    fi
else
    kk_test_pass "Check broken symlink with FollowLink=false (skipped: symlinks not supported)"
fi

# Test 7: Invalid path
kk_test_start "Check invalid path"
result=$(tfile.exists "/invalid/path/file.tmp")
if [[ $result == false ]]; then
    kk_test_pass "Check invalid path"
else
    kk_test_fail "Check invalid path"
fi
