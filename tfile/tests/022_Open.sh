#!/bin/bash
# 022_open.sh - Test TFile.Open method
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

# Test 1: Open existing file for read
kk_test_start "Open existing file for read"
echo "content" > "$KK_TEST_TMPDIR/open_read.tmp"
stream=$(tfile.open "$KK_TEST_TMPDIR/open_read.tmp" "fmOpenRead")
if [[ -n "$stream" ]]; then
    kk_test_pass "Open existing file for read"
else
kk_test_fail "Open existing file for read"
fi

# Test 2: Open for write (creates if not exists)
kk_test_start "Open for write"
stream=$(tfile.open "$KK_TEST_TMPDIR/open_write.tmp" "fmOpenWrite")
if [[ -f "$KK_TEST_TMPDIR/open_write.tmp" ]]; then
    kk_test_pass "Open for write"
else
    kk_test_fail "Open for write"
fi

# Test 3: Open with access and share
kk_test_start "Open with access and share"
echo "content" > "$KK_TEST_TMPDIR/open_access.tmp"
stream=$(tfile.open "$KK_TEST_TMPDIR/open_access.tmp" "fmOpenReadWrite" "faReadWrite" "fsReadWrite")
if [[ -n "$stream" ]]; then
    kk_test_pass "Open with access and share"
else
    kk_test_fail "Open with access and share"
fi

# Test 4: Open non-existing file for read
kk_test_start "Open non-existing file for read"
rm -f "$KK_TEST_TMPDIR/nonexistent.tmp"
stream=$(tfile.open "$KK_TEST_TMPDIR/nonexistent.tmp" "fmOpenRead" 2>/dev/null)
if [[ -z "$stream" ]]; then
    kk_test_pass "Open non-existing file for read (correctly failed)"
else
    kk_test_fail "Open non-existing file for read (should have failed)"
fi
