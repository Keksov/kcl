#!/bin/bash
# 023_open_read.sh - Test TFile.OpenRead method
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

# Test 1: Open existing file for read
kt_test_start "Open existing file for read"
echo "content" > "$_KT_TMPDIR/openread.tmp"
stream=$(tfile.openRead "$_KT_TMPDIR/openread.tmp")
if [[ -n "$stream" ]]; then
    kt_test_pass "Open existing file for read"
else
kt_test_fail "Open existing file for read"
fi

# Test 2: Open non-existing file
kt_test_start "Open non-existing file"
rm -f "$_KT_TMPDIR/nonexistent.tmp"
if ! stream=$(tfile.openRead "$_KT_TMPDIR/nonexistent.tmp" 2>&1); then
    kt_test_pass "Open non-existing file (correctly failed)"
else
    kt_test_fail "Open non-existing file (should have failed)"
fi
