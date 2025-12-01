#!/bin/bash
# 019_get_sym_link_target.sh - Test TFile.GetSymLinkTarget method
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

# Create test file for test 4
echo "target" > "$_KT_TMPDIR/sym_target.tmp"

if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    # Test 1: Get target of valid symlink
kt_test_start "Get target of valid symlink"
ln -s "$_KT_TMPDIR/sym_target.tmp" "$_KT_TMPDIR/sym.tmp"
    result=$(tfile.getSymLinkTarget "$_KT_TMPDIR/sym.tmp")
    if [[ -n "$result" ]]; then
        kt_test_pass "Get target of valid symlink"
else
        kt_test_fail "Get target of valid symlink"
fi

    # Test 2: Get target string of valid symlink
    kt_test_start "Get target string of valid symlink"
    target=$(tfile.getSymLinkTarget "$_KT_TMPDIR/sym.tmp")
    if [[ "$target" == "$_KT_TMPDIR/sym_target.tmp" ]]; then
        kt_test_pass "Get target string of valid symlink"
    else
    kt_test_fail "Get target string of valid symlink (expected: $_KT_TMPDIR/sym_target.tmp, got: $target)"
    fi

    # Test 3: Get target of broken symlink
    kt_test_start "Get target of broken symlink"
    ln -s "$_KT_TMPDIR/nonexist.tmp" "$_KT_TMPDIR/broken_sym.tmp"
    result=$(tfile.getSymLinkTarget "$_KT_TMPDIR/broken_sym.tmp")
    if [[ -n "$result" ]]; then
        kt_test_pass "Get target of broken symlink"
else
        kt_test_fail "Get target of broken symlink"
fi
else
    kt_test_pass "Get target of valid symlink (skipped: symlinks not supported)"
    kt_test_pass "Get target string of valid symlink (skipped: symlinks not supported)"
    kt_test_pass "Get target of broken symlink (skipped: symlinks not supported)"
fi

# Test 4: Get target of regular file
kt_test_start "Get target of regular file"
result=$(tfile.getSymLinkTarget "$_KT_TMPDIR/sym_target.tmp")
if [[ -z "$result" ]]; then
    kt_test_pass "Get target of regular file"
else
    kt_test_fail "Get target of regular file"
fi
