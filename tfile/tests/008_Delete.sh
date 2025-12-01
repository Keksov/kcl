#!/bin/bash
# 008_delete.sh - Test TFile.Delete method
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

# Test 1: Delete existing file
kt_test_start "Delete existing file"
echo "content" > "$_KT_TMPDIR/delete.tmp"
result=$(tfile.delete "$_KT_TMPDIR/delete.tmp")
if [[ ! -f "$_KT_TMPDIR/delete.tmp" ]]; then
    kt_test_pass "Delete existing file"
else
    kt_test_fail "Delete existing file"
fi

# Test 2: Delete non-existing file
kt_test_start "Delete non-existing file"
if ! result=$(tfile.delete "$_KT_TMPDIR/nonexist.tmp" 2>&1); then
    kt_test_pass "Delete non-existing file (correctly failed)"
else
    kt_test_fail "Delete non-existing file (should have failed)"
fi

# Test 3: Delete directory (should fail)
kt_test_start "Delete directory"
mkdir -p "$_KT_TMPDIR/delete_dir"
if ! result=$(tfile.delete "$_KT_TMPDIR/delete_dir" 2>&1); then
    kt_test_pass "Delete directory (correctly failed)"
else
    kt_test_fail "Delete directory (should have failed)"
fi

# Test 4: Delete with invalid path
kt_test_start "Delete with invalid path"
if ! result=$(tfile.delete "/invalid/path/file.tmp" 2>&1); then
    kt_test_pass "Delete with invalid path (correctly failed)"
else
    kt_test_fail "Delete with invalid path (should have failed)"
fi
