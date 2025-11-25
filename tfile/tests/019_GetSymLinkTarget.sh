#!/bin/bash
# 019_get_sym_link_target.sh - Test TFile.GetSymLinkTarget method
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

# Create test file for test 4
echo "target" > "$KK_TEST_TMPDIR/sym_target.tmp"

if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    # Test 1: Get target of valid symlink
kk_test_start "Get target of valid symlink"
ln -s "$KK_TEST_TMPDIR/sym_target.tmp" "$KK_TEST_TMPDIR/sym.tmp"
    result=$(tfile.getSymLinkTarget "$KK_TEST_TMPDIR/sym.tmp")
    if [[ -n "$result" ]]; then
        kk_test_pass "Get target of valid symlink"
else
        kk_test_fail "Get target of valid symlink"
fi

    # Test 2: Get target string of valid symlink
    kk_test_start "Get target string of valid symlink"
    target=$(tfile.getSymLinkTarget "$KK_TEST_TMPDIR/sym.tmp")
    if [[ "$target" == "$KK_TEST_TMPDIR/sym_target.tmp" ]]; then
        kk_test_pass "Get target string of valid symlink"
    else
    kk_test_fail "Get target string of valid symlink (expected: $KK_TEST_TMPDIR/sym_target.tmp, got: $target)"
    fi

    # Test 3: Get target of broken symlink
    kk_test_start "Get target of broken symlink"
    ln -s "$KK_TEST_TMPDIR/nonexist.tmp" "$KK_TEST_TMPDIR/broken_sym.tmp"
    result=$(tfile.getSymLinkTarget "$KK_TEST_TMPDIR/broken_sym.tmp")
    if [[ -n "$result" ]]; then
        kk_test_pass "Get target of broken symlink"
else
        kk_test_fail "Get target of broken symlink"
fi
else
    kk_test_pass "Get target of valid symlink (skipped: symlinks not supported)"
    kk_test_pass "Get target string of valid symlink (skipped: symlinks not supported)"
    kk_test_pass "Get target of broken symlink (skipped: symlinks not supported)"
fi

# Test 4: Get target of regular file
kk_test_start "Get target of regular file"
result=$(tfile.getSymLinkTarget "$KK_TEST_TMPDIR/sym_target.tmp")
if [[ -z "$result" ]]; then
    kk_test_pass "Get target of regular file"
else
    kk_test_fail "Get target of regular file"
fi
