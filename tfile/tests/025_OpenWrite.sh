#!/bin/bash
# 025_open_write.sh - Test TFile.OpenWrite method
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

# Test 1: Open existing file for write
kt_test_start "Open existing file for write"
echo "old" > "$_KT_TMPDIR/openwrite.tmp"
stream=$(tfile.openWrite "$_KT_TMPDIR/openwrite.tmp")
if [[ -n "$stream" ]]; then
    kt_test_pass "Open existing file for write"
else
kt_test_fail "Open existing file for write"
fi

# Test 2: Open non-existing file for write
kt_test_start "Open non-existing file for write"
stream=$(tfile.openWrite "$_KT_TMPDIR/openwrite_new.tmp")
if [[ -f "$_KT_TMPDIR/openwrite_new.tmp" ]]; then
    kt_test_pass "Open non-existing file for write"
else
    kt_test_fail "Open non-existing file for write"
fi
