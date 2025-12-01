#!/bin/bash
# 004_create.sh - Test TFile.Create method
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


# Initialize test-specific temporary directory

# Test 1: Create new file
kt_test_start "Create new file"
rm -f "$_KT_TMPDIR/create.tmp"
stream=$(tfile.create "$_KT_TMPDIR/create.tmp")
if [[ -f "$_KT_TMPDIR/create.tmp" ]]; then
    kt_test_pass "Create new file"
    # close_stream "$stream"
else
    kt_test_fail "Create new file"
fi

# Test 2: Create with buffer size
kt_test_start "Create with buffer size"
rm -f "$_KT_TMPDIR/create_buf.tmp"
stream=$(tfile.create "$_KT_TMPDIR/create_buf.tmp" 8192)
if [[ -f "$_KT_TMPDIR/create_buf.tmp" ]]; then
    kt_test_pass "Create with buffer size"
    # close_stream "$stream"
else
    kt_test_fail "Create with buffer size"
fi

# Test 3: Create existing file (should overwrite)
kt_test_start "Create existing file"
printf "old" > "$_KT_TMPDIR/overwrite.tmp"
stream=$(tfile.create "$_KT_TMPDIR/overwrite.tmp")
if [[ -f "$_KT_TMPDIR/overwrite.tmp" && ! -s "$_KT_TMPDIR/overwrite.tmp" ]]; then
    kt_test_pass "Create existing file"
    # close_stream "$stream"
else
    kt_test_fail "Create existing file"
fi

# Test 4: Create in invalid path
kt_test_start "Create in invalid path"
if ! stream=$(tfile.create "/invalid/path/file.tmp" 2>&1); then
    kt_test_pass "Create in invalid path (correctly failed)"
else
    kt_test_fail "Create in invalid path (should have failed)"
fi
