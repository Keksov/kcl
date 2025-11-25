#!/bin/bash
# 004_create.sh - Test TFile.Create method
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


# Initialize test-specific temporary directory

# Test 1: Create new file
kk_test_start "Create new file"
rm -f "$KK_TEST_TMPDIR/create.tmp"
stream=$(tfile.create "$KK_TEST_TMPDIR/create.tmp")
if [[ -f "$KK_TEST_TMPDIR/create.tmp" ]]; then
    kk_test_pass "Create new file"
    # close_stream "$stream"
else
    kk_test_fail "Create new file"
fi

# Test 2: Create with buffer size
kk_test_start "Create with buffer size"
rm -f "$KK_TEST_TMPDIR/create_buf.tmp"
stream=$(tfile.create "$KK_TEST_TMPDIR/create_buf.tmp" 8192)
if [[ -f "$KK_TEST_TMPDIR/create_buf.tmp" ]]; then
    kk_test_pass "Create with buffer size"
    # close_stream "$stream"
else
    kk_test_fail "Create with buffer size"
fi

# Test 3: Create existing file (should overwrite)
kk_test_start "Create existing file"
printf "old" > "$KK_TEST_TMPDIR/overwrite.tmp"
stream=$(tfile.create "$KK_TEST_TMPDIR/overwrite.tmp")
if [[ -f "$KK_TEST_TMPDIR/overwrite.tmp" && ! -s "$KK_TEST_TMPDIR/overwrite.tmp" ]]; then
    kk_test_pass "Create existing file"
    # close_stream "$stream"
else
    kk_test_fail "Create existing file"
fi

# Test 4: Create in invalid path
kk_test_start "Create in invalid path"
if ! stream=$(tfile.create "/invalid/path/file.tmp" 2>&1); then
    kk_test_pass "Create in invalid path (correctly failed)"
else
    kk_test_fail "Create in invalid path (should have failed)"
fi
