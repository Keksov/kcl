#!/bin/bash
# 024_open_text.sh - Test TFile.OpenText method
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

# Test 1: Open existing text file
kt_test_start "Open existing text file"
echo "text content" > "$_KT_TMPDIR/opentext.tmp"
reader=$(tfile.openText "$_KT_TMPDIR/opentext.tmp")
if [[ -n "$reader" ]]; then
    kt_test_pass "Open existing text file"
else
kt_test_fail "Open existing text file"
fi

# Test 2: Open non-existing file
kt_test_start "Open non-existing text file"
rm -f "$_KT_TMPDIR/nonexist.tmp"
if ! reader=$(tfile.openText "$_KT_TMPDIR/nonexist.tmp" 2>&1); then
    kt_test_pass "Open non-existing text file (correctly failed)"
else
    kt_test_fail "Open non-existing text file (should have failed)"
fi
