#!/bin/bash
# 012_get_attributes.sh - Test TFile.GetAttributes method
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

# Test 1: Get attributes of existing file
kk_test_start "Get attributes of existing file"
echo "content" > "$KK_TEST_TMPDIR/attr.tmp"
result=$(tfile.getAttributes "$KK_TEST_TMPDIR/attr.tmp")
if [[ -n "$result" ]]; then
    kk_test_pass "Get attributes of existing file"
else
    kk_test_fail "Get attributes of existing file"
fi

# Test 2: Get attributes of non-existing file
kk_test_start "Get attributes of non-existing file"
if ! result=$(tfile.getAttributes "$KK_TEST_TMPDIR/nonexist.tmp" 2>&1); then
    kk_test_pass "Get attributes of non-existing file (correctly failed)"
else
    kk_test_fail "Get attributes of non-existing file (should have failed)"
fi

if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    # Test 3: Get attributes with FollowLink=true
    kk_test_start "Get attributes with FollowLink=true"
    echo "target" > "$KK_TEST_TMPDIR/attr_target.tmp"
    ln -s "$KK_TEST_TMPDIR/attr_target.tmp" "$KK_TEST_TMPDIR/attr_link.tmp"
    result=$(tfile.getAttributes "$KK_TEST_TMPDIR/attr_link.tmp" true)
    if [[ -n "$result" ]]; then
        kk_test_pass "Get attributes with FollowLink=true"
    else
        kk_test_fail "Get attributes with FollowLink=true"
    fi

    # Test 4: Get attributes of broken symlink with FollowLink=true
    kk_test_start "Get attributes of broken symlink with FollowLink=true"
    ln -s "$KK_TEST_TMPDIR/nonexist.tmp" "$KK_TEST_TMPDIR/attr_broken.tmp"
    if ! result=$(tfile.getAttributes "$KK_TEST_TMPDIR/attr_broken.tmp" true 2>&1); then
        kk_test_pass "Get attributes of broken symlink with FollowLink=true (correctly failed)"
    else
        kk_test_fail "Get attributes of broken symlink with FollowLink=true (should have failed)"
    fi
else
    kk_test_pass "Get attributes with FollowLink=true (skipped: symlinks not supported)"
    kk_test_pass "Get attributes of broken symlink with FollowLink=true (skipped: symlinks not supported)"
fi
