#!/bin/bash
# 030_set_attributes.sh - Test TFile.SetAttributes method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "030"

# Test 1: Set attributes on existing file
test_start "Set attributes on existing file"
echo "content" > "$TEST_TMP_DIR/setattr.tmp"
result=$(tfile.setAttributes "$TEST_TMP_DIR/setattr.tmp" "[ReadOnly]")
if [[ $? -eq 0 ]]; then
    test_pass "Set attributes on existing file"
else
    test_fail "Set attributes on existing file"
fi

# Test 2: Set attributes on non-existing file
test_start "Set attributes on non-existing file"
if ! result=$(tfile.setAttributes "$TEST_TMP_DIR/nonexist.tmp" "[ReadOnly]" 2>&1); then
    test_pass "Set attributes on non-existing file (correctly failed)"
else
    test_fail "Set attributes on non-existing file (should have failed)"
fi
