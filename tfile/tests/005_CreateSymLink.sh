#!/bin/bash
# 005_create_sym_link.sh - Test TFile.CreateSymLink method
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

if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
# Test 1: Create symlink to existing file
kt_test_start "Create symlink to existing file"
echo "target content" > "$_KT_TMPDIR/target.tmp"
result=$(tfile.createSymLink "$_KT_TMPDIR/link.tmp" "$_KT_TMPDIR/target.tmp")
if [[ $result == true ]]; then
kt_test_pass "Create symlink to existing file"
else
kt_test_fail "Create symlink to existing file"
fi

# Test 2: Create symlink to directory
kt_test_start "Create symlink to directory"
mkdir -p "$_KT_TMPDIR/test_dir"
result=$(tfile.createSymLink "$_KT_TMPDIR/dir_link.tmp" "$_KT_TMPDIR/test_dir")
if [[ $result == true ]]; then
kt_test_pass "Create symlink to directory"
else
kt_test_fail "Create symlink to directory"
fi

# Test 3: Create symlink to non-existing target
kt_test_start "Create symlink to non-existing target"
if [[ $(tfile.createSymLink "$_KT_TMPDIR/broken.tmp" "$_KT_TMPDIR/nonexist.tmp") == false ]]; then
    kt_test_pass "Create symlink to non-existing target (correctly failed)"
else
    kt_test_fail "Create symlink to non-existing target (should have failed)"
fi

# Test 4: Invalid link path
kt_test_start "Create symlink with invalid link path"
if ! result=$(tfile.createSymLink "/invalid/path/link.tmp" "$_KT_TMPDIR/target.tmp" 2>&1); then
kt_test_pass "Create symlink with invalid link path (correctly failed)"
else
kt_test_fail "Create symlink with invalid link path (should have failed)"
fi
else
    kt_test_pass "Create symlink to existing file (skipped: symlinks not supported)"
    kt_test_pass "Create symlink to directory (skipped: symlinks not supported)"
    kt_test_pass "Create symlink to non-existing target (skipped: symlinks not supported)"
    kt_test_pass "Create symlink with invalid link path (skipped: symlinks not supported)"
fi
