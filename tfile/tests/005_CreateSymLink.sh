#!/bin/bash
# 005_create_sym_link.sh - Test TFile.CreateSymLink method
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

if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
# Test 1: Create symlink to existing file
kk_test_start "Create symlink to existing file"
echo "target content" > "$KK_TEST_TMPDIR/target.tmp"
result=$(tfile.createSymLink "$KK_TEST_TMPDIR/link.tmp" "$KK_TEST_TMPDIR/target.tmp")
if [[ $result == true ]]; then
kk_test_pass "Create symlink to existing file"
else
kk_test_fail "Create symlink to existing file"
fi

# Test 2: Create symlink to directory
kk_test_start "Create symlink to directory"
mkdir -p "$KK_TEST_TMPDIR/test_dir"
result=$(tfile.createSymLink "$KK_TEST_TMPDIR/dir_link.tmp" "$KK_TEST_TMPDIR/test_dir")
if [[ $result == true ]]; then
kk_test_pass "Create symlink to directory"
else
kk_test_fail "Create symlink to directory"
fi

# Test 3: Create symlink to non-existing target
kk_test_start "Create symlink to non-existing target"
if [[ $(tfile.createSymLink "$KK_TEST_TMPDIR/broken.tmp" "$KK_TEST_TMPDIR/nonexist.tmp") == false ]]; then
    kk_test_pass "Create symlink to non-existing target (correctly failed)"
else
    kk_test_fail "Create symlink to non-existing target (should have failed)"
fi

# Test 4: Invalid link path
kk_test_start "Create symlink with invalid link path"
if ! result=$(tfile.createSymLink "/invalid/path/link.tmp" "$KK_TEST_TMPDIR/target.tmp" 2>&1); then
kk_test_pass "Create symlink with invalid link path (correctly failed)"
else
kk_test_fail "Create symlink with invalid link path (should have failed)"
fi
else
    kk_test_pass "Create symlink to existing file (skipped: symlinks not supported)"
    kk_test_pass "Create symlink to directory (skipped: symlinks not supported)"
    kk_test_pass "Create symlink to non-existing target (skipped: symlinks not supported)"
    kk_test_pass "Create symlink with invalid link path (skipped: symlinks not supported)"
fi
