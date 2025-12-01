#!/bin/bash
# 022_open.sh - Test TFile.Open method
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

# Test 1: Open existing file for read
kt_test_start "Open existing file for read"
echo "content" > "$_KT_TMPDIR/open_read.tmp"
stream=$(tfile.open "$_KT_TMPDIR/open_read.tmp" "fmOpenRead")
if [[ -n "$stream" ]]; then
    kt_test_pass "Open existing file for read"
else
kt_test_fail "Open existing file for read"
fi

# Test 2: Open for write (creates if not exists)
kt_test_start "Open for write"
stream=$(tfile.open "$_KT_TMPDIR/open_write.tmp" "fmOpenWrite")
if [[ -f "$_KT_TMPDIR/open_write.tmp" ]]; then
    kt_test_pass "Open for write"
else
    kt_test_fail "Open for write"
fi

# Test 3: Open with access and share
kt_test_start "Open with access and share"
echo "content" > "$_KT_TMPDIR/open_access.tmp"
stream=$(tfile.open "$_KT_TMPDIR/open_access.tmp" "fmOpenReadWrite" "faReadWrite" "fsReadWrite")
if [[ -n "$stream" ]]; then
    kt_test_pass "Open with access and share"
else
    kt_test_fail "Open with access and share"
fi

# Test 4: Open non-existing file for read
kt_test_start "Open non-existing file for read"
rm -f "$_KT_TMPDIR/nonexistent.tmp"
stream=$(tfile.open "$_KT_TMPDIR/nonexistent.tmp" "fmOpenRead" 2>/dev/null)
if [[ -z "$stream" ]]; then
    kt_test_pass "Open non-existing file for read (correctly failed)"
else
    kt_test_fail "Open non-existing file for read (should have failed)"
fi
