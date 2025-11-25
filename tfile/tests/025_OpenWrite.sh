#!/bin/bash
# 025_open_write.sh - Test TFile.OpenWrite method
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

# Test 1: Open existing file for write
kk_test_start "Open existing file for write"
echo "old" > "$KK_TEST_TMPDIR/openwrite.tmp"
stream=$(tfile.openWrite "$KK_TEST_TMPDIR/openwrite.tmp")
if [[ -n "$stream" ]]; then
    kk_test_pass "Open existing file for write"
else
kk_test_fail "Open existing file for write"
fi

# Test 2: Open non-existing file for write
kk_test_start "Open non-existing file for write"
stream=$(tfile.openWrite "$KK_TEST_TMPDIR/openwrite_new.tmp")
if [[ -f "$KK_TEST_TMPDIR/openwrite_new.tmp" ]]; then
    kk_test_pass "Open non-existing file for write"
else
    kk_test_fail "Open non-existing file for write"
fi
