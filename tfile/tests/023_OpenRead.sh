#!/bin/bash
# 023_open_read.sh - Test TFile.OpenRead method
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

# Test 1: Open existing file for read
kk_test_start "Open existing file for read"
echo "content" > "$KK_TEST_TMPDIR/openread.tmp"
stream=$(tfile.openRead "$KK_TEST_TMPDIR/openread.tmp")
if [[ -n "$stream" ]]; then
    kk_test_pass "Open existing file for read"
else
kk_test_fail "Open existing file for read"
fi

# Test 2: Open non-existing file
kk_test_start "Open non-existing file"
rm -f "$KK_TEST_TMPDIR/nonexistent.tmp"
if ! stream=$(tfile.openRead "$KK_TEST_TMPDIR/nonexistent.tmp" 2>&1); then
    kk_test_pass "Open non-existing file (correctly failed)"
else
    kk_test_fail "Open non-existing file (should have failed)"
fi
