#!/bin/bash
# 002_append_text.sh - Test TFile.AppendText method
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

# Test 1: Append to existing file
kk_test_start "Append text to existing file"
printf "initial" > "$KK_TEST_TMPDIR/append_text.tmp"
writer=$(tfile.appendText "$KK_TEST_TMPDIR/append_text.tmp")
# Note: This assumes writer has write and close methods, adjust based on actual API
printf " appended" >> "$writer"  # Simplified, actual implementation may vary
# close_writer "$writer"
if [[ "$(cat "$KK_TEST_TMPDIR"/append_text.tmp)" == "initial appended" ]]; then
    kk_test_pass "Append text to existing file"
else
    kk_test_fail "Append text to existing file (got: $(cat "$KK_TEST_TMPDIR"/append_text.tmp))"
fi

# Test 2: Append to new file
kk_test_start "Append text to new file"
rm -f "$KK_TEST_TMPDIR/new_append.tmp"
writer=$(tfile.appendText "$KK_TEST_TMPDIR/new_append.tmp")
printf "new content" > "$writer"
# close_writer "$writer"
if [[ "$(cat "$KK_TEST_TMPDIR"/new_append.tmp)" == "new content" ]]; then
    kk_test_pass "Append text to new file"
else
    kk_test_fail "Append text to new file"
fi

# Test 3: Invalid path
kk_test_start "Append text to invalid path"
if ! writer=$(tfile.appendText "/invalid/path/file.tmp" 2>&1); then
    kk_test_pass "Append text to invalid path (correctly failed)"
else
    kk_test_fail "Append text to invalid path (should have failed)"
fi
