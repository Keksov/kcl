#!/bin/bash
# 021_move.sh - Test TFile.Move method
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

# Test 1: Move existing file
kk_test_start "Move existing file"
echo "content" > "$KK_TEST_TMPDIR/move_source.tmp"
result=$(tfile.move "$KK_TEST_TMPDIR/move_source.tmp" "$KK_TEST_TMPDIR/move_dest.tmp")
if [[ ! -f "$KK_TEST_TMPDIR/move_source.tmp" && -f "$KK_TEST_TMPDIR/move_dest.tmp" && "$(cat "$KK_TEST_TMPDIR"/move_dest.tmp)" == "content" ]]; then
    kk_test_pass "Move existing file"
else
    kk_test_fail "Move existing file"
fi

# Test 2: Move to existing destination
kk_test_start "Move to existing destination"
echo "source2" > "$KK_TEST_TMPDIR/move_source2.tmp"
echo "dest2" > "$KK_TEST_TMPDIR/move_dest2.tmp"
if ! result=$(tfile.move "$KK_TEST_TMPDIR/move_source2.tmp" "$KK_TEST_TMPDIR/move_dest2.tmp" 2>&1); then
    kk_test_pass "Move to existing destination (correctly failed)"
else
    kk_test_fail "Move to existing destination (should have failed)"
fi

# Test 3: Move non-existing source
kk_test_start "Move non-existing source"
if ! result=$(tfile.move "$KK_TEST_TMPDIR/nonexist.tmp" "$KK_TEST_TMPDIR/dest.tmp" 2>&1); then
    kk_test_pass "Move non-existing source (correctly failed)"
else
    kk_test_fail "Move non-existing source (should have failed)"
fi

# Test 4: Move to invalid path
kk_test_start "Move to invalid path"
echo "source3" > "$KK_TEST_TMPDIR/move_source3.tmp"
if ! result=$(tfile.move "$KK_TEST_TMPDIR/move_source3.tmp" "/invalid/path/file.tmp" 2>&1); then
    kk_test_pass "Move to invalid path (correctly failed)"
else
    kk_test_fail "Move to invalid path (should have failed)"
fi
