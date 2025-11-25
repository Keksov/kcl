#!/bin/bash
# 030_set_attributes.sh - Test TFile.SetAttributes method
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

# Test 1: Set attributes on existing file
kk_test_start "Set attributes on existing file"
echo "content" > "$KK_TEST_TMPDIR/setattr.tmp"
result=$(tfile.setAttributes "$KK_TEST_TMPDIR/setattr.tmp" "[ReadOnly]")
if [[ $? -eq 0 ]]; then
    kk_test_pass "Set attributes on existing file"
else
    kk_test_fail "Set attributes on existing file"
fi

# Test 2: Set attributes on non-existing file
kk_test_start "Set attributes on non-existing file"
if ! result=$(tfile.setAttributes "$KK_TEST_TMPDIR/nonexist.tmp" "[ReadOnly]" 2>&1); then
    kk_test_pass "Set attributes on non-existing file (correctly failed)"
else
    kk_test_fail "Set attributes on non-existing file (should have failed)"
fi
