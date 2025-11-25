#!/bin/bash
# 008_delete.sh - Test TFile.Delete method
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

# Test 1: Delete existing file
kk_test_start "Delete existing file"
echo "content" > "$KK_TEST_TMPDIR/delete.tmp"
result=$(tfile.delete "$KK_TEST_TMPDIR/delete.tmp")
if [[ ! -f "$KK_TEST_TMPDIR/delete.tmp" ]]; then
    kk_test_pass "Delete existing file"
else
    kk_test_fail "Delete existing file"
fi

# Test 2: Delete non-existing file
kk_test_start "Delete non-existing file"
if ! result=$(tfile.delete "$KK_TEST_TMPDIR/nonexist.tmp" 2>&1); then
    kk_test_pass "Delete non-existing file (correctly failed)"
else
    kk_test_fail "Delete non-existing file (should have failed)"
fi

# Test 3: Delete directory (should fail)
kk_test_start "Delete directory"
mkdir -p "$KK_TEST_TMPDIR/delete_dir"
if ! result=$(tfile.delete "$KK_TEST_TMPDIR/delete_dir" 2>&1); then
    kk_test_pass "Delete directory (correctly failed)"
else
    kk_test_fail "Delete directory (should have failed)"
fi

# Test 4: Delete with invalid path
kk_test_start "Delete with invalid path"
if ! result=$(tfile.delete "/invalid/path/file.tmp" 2>&1); then
    kk_test_pass "Delete with invalid path (correctly failed)"
else
    kk_test_fail "Delete with invalid path (should have failed)"
fi
