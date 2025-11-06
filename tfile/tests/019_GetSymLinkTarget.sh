#!/bin/bash
# 019_get_sym_link_target.sh - Test TFile.GetSymLinkTarget method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "019"

# Check if symlinks are supported
if ln -s "$TEST_TMP_DIR/nonexist.tmp" "$TEST_TMP_DIR/test_link.tmp" 2>/dev/null; then
SYMLINK_SUPPORTED=true
rm -f "$TEST_TMP_DIR/test_link.tmp"
else
SYMLINK_SUPPORTED=false
fi

# Create test file for test 4
echo "target" > "$TEST_TMP_DIR/sym_target.tmp"

if [[ "$SYMLINK_SUPPORTED" == "true" ]]; then
    # Test 1: Get target of valid symlink
test_start "Get target of valid symlink"
ln -s "$TEST_TMP_DIR/sym_target.tmp" "$TEST_TMP_DIR/sym.tmp"
    result=$(tfile.getSymLinkTarget "$TEST_TMP_DIR/sym.tmp")
    if [[ -n "$result" ]]; then
        test_pass "Get target of valid symlink"
else
        test_fail "Get target of valid symlink"
fi

    # Test 2: Get target string of valid symlink
    test_start "Get target string of valid symlink"
    target=$(tfile.getSymLinkTarget "$TEST_TMP_DIR/sym.tmp")
    if [[ "$target" == "$TEST_TMP_DIR/sym_target.tmp" ]]; then
        test_pass "Get target string of valid symlink"
    else
    test_fail "Get target string of valid symlink (expected: $TEST_TMP_DIR/sym_target.tmp, got: $target)"
    fi

    # Test 3: Get target of broken symlink
    test_start "Get target of broken symlink"
    ln -s "$TEST_TMP_DIR/nonexist.tmp" "$TEST_TMP_DIR/broken_sym.tmp"
    result=$(tfile.getSymLinkTarget "$TEST_TMP_DIR/broken_sym.tmp")
    if [[ -n "$result" ]]; then
        test_pass "Get target of broken symlink"
else
        test_fail "Get target of broken symlink"
fi
else
    test_pass "Get target of valid symlink (skipped: symlinks not supported)"
    test_pass "Get target string of valid symlink (skipped: symlinks not supported)"
    test_pass "Get target of broken symlink (skipped: symlinks not supported)"
fi

# Test 4: Get target of regular file
test_start "Get target of regular file"
result=$(tfile.getSymLinkTarget "$TEST_TMP_DIR/sym_target.tmp")
if [[ -z "$result" ]]; then
    test_pass "Get target of regular file"
else
    test_fail "Get target of regular file"
fi
