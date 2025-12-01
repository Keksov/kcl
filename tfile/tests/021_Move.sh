#!/bin/bash
# 021_move.sh - Test TFile.Move method
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

# Test 1: Move existing file
kt_test_start "Move existing file"
echo "content" > "$_KT_TMPDIR/move_source.tmp"
result=$(tfile.move "$_KT_TMPDIR/move_source.tmp" "$_KT_TMPDIR/move_dest.tmp")
if [[ ! -f "$_KT_TMPDIR/move_source.tmp" && -f "$_KT_TMPDIR/move_dest.tmp" && "$(cat "$_KT_TMPDIR"/move_dest.tmp)" == "content" ]]; then
    kt_test_pass "Move existing file"
else
    kt_test_fail "Move existing file"
fi

# Test 2: Move to existing destination
kt_test_start "Move to existing destination"
echo "source2" > "$_KT_TMPDIR/move_source2.tmp"
echo "dest2" > "$_KT_TMPDIR/move_dest2.tmp"
if ! result=$(tfile.move "$_KT_TMPDIR/move_source2.tmp" "$_KT_TMPDIR/move_dest2.tmp" 2>&1); then
    kt_test_pass "Move to existing destination (correctly failed)"
else
    kt_test_fail "Move to existing destination (should have failed)"
fi

# Test 3: Move non-existing source
kt_test_start "Move non-existing source"
if ! result=$(tfile.move "$_KT_TMPDIR/nonexist.tmp" "$_KT_TMPDIR/dest.tmp" 2>&1); then
    kt_test_pass "Move non-existing source (correctly failed)"
else
    kt_test_fail "Move non-existing source (should have failed)"
fi

# Test 4: Move to invalid path
kt_test_start "Move to invalid path"
echo "source3" > "$_KT_TMPDIR/move_source3.tmp"
if ! result=$(tfile.move "$_KT_TMPDIR/move_source3.tmp" "/invalid/path/file.tmp" 2>&1); then
    kt_test_pass "Move to invalid path (correctly failed)"
else
    kt_test_fail "Move to invalid path (should have failed)"
fi
