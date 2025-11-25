#!/bin/bash
# 024_open_text.sh - Test TFile.OpenText method
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

# Test 1: Open existing text file
kk_test_start "Open existing text file"
echo "text content" > "$KK_TEST_TMPDIR/opentext.tmp"
reader=$(tfile.openText "$KK_TEST_TMPDIR/opentext.tmp")
if [[ -n "$reader" ]]; then
    kk_test_pass "Open existing text file"
else
kk_test_fail "Open existing text file"
fi

# Test 2: Open non-existing file
kk_test_start "Open non-existing text file"
rm -f "$KK_TEST_TMPDIR/nonexist.tmp"
if ! reader=$(tfile.openText "$KK_TEST_TMPDIR/nonexist.tmp" 2>&1); then
    kk_test_pass "Open non-existing text file (correctly failed)"
else
    kk_test_fail "Open non-existing text file (should have failed)"
fi
