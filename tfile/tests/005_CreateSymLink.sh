#!/bin/bash
# 005_create_sym_link.sh - Test TFile.CreateSymLink method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "005"

# Check if symlinks are supported
if ln -s "$TEST_TMP_DIR/nonexist.tmp" "$TEST_TMP_DIR/test_link.tmp" 2>/dev/null; then
    SYMLINK_SUPPORTED=true
    rm -f "$TEST_TMP_DIR/test_link.tmp"
else
    SYMLINK_SUPPORTED=false
fi

if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
# Test 1: Create symlink to existing file
test_start "Create symlink to existing file"
echo "target content" > "$TEST_TMP_DIR/target.tmp"
result=$(tfile.createSymLink "$TEST_TMP_DIR/link.tmp" "$TEST_TMP_DIR/target.tmp")
if [[ $result == true ]]; then
test_pass "Create symlink to existing file"
else
test_fail "Create symlink to existing file"
fi

# Test 2: Create symlink to directory
test_start "Create symlink to directory"
mkdir -p "$TEST_TMP_DIR/test_dir"
result=$(tfile.createSymLink "$TEST_TMP_DIR/dir_link.tmp" "$TEST_TMP_DIR/test_dir")
if [[ $result == true ]]; then
test_pass "Create symlink to directory"
else
test_fail "Create symlink to directory"
fi

# Test 3: Create symlink to non-existing target
test_start "Create symlink to non-existing target"
if [[ $(tfile.createSymLink "$TEST_TMP_DIR/broken.tmp" "$TEST_TMP_DIR/nonexist.tmp") == false ]]; then
    test_pass "Create symlink to non-existing target (correctly failed)"
else
    test_fail "Create symlink to non-existing target (should have failed)"
fi

# Test 4: Invalid link path
test_start "Create symlink with invalid link path"
if ! result=$(tfile.createSymLink "/invalid/path/link.tmp" "$TEST_TMP_DIR/target.tmp" 2>&1); then
test_pass "Create symlink with invalid link path (correctly failed)"
else
test_fail "Create symlink with invalid link path (should have failed)"
fi
else
    test_pass "Create symlink to existing file (skipped: symlinks not supported)"
    test_pass "Create symlink to directory (skipped: symlinks not supported)"
    test_pass "Create symlink to non-existing target (skipped: symlinks not supported)"
    test_pass "Create symlink with invalid link path (skipped: symlinks not supported)"
fi
