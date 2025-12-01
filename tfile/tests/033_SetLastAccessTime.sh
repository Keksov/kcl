#!/bin/bash
# 033_set_last_access_time.sh - Test TFile.SetLastAccessTime method
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


# Test 1: Set last access time on existing file
kt_test_start "Set last access time on existing file"
echo "content" > "$_KT_TMPDIR/setaccess.tmp"
now=$(date +%s)
result=$(tfile.setLastAccessTime "$_KT_TMPDIR/setaccess.tmp" "$now")
if [[ $? -eq 0 ]]; then
kt_test_pass "Set last access time on existing file"
else
kt_test_fail "Set last access time on existing file"
fi

# Test 2: Set last access time on non-existing file
kt_test_start "Set last access time on non-existing file"
if ! result=$(tfile.setLastAccessTime "$_KT_TMPDIR/nonexist.tmp" "$now" 2>&1); then
kt_test_pass "Set last access time on non-existing file (correctly failed)"
else
kt_test_fail "Set last access time on non-existing file (should have failed)"
fi
