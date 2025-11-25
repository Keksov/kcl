#!/bin/bash
# 006_create_text.sh - Test TFile.CreateText method
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

# Test 1: Create new text file
kk_test_start "Create new text file"
writer=$(tfile.createText "$KK_TEST_TMPDIR/create_text.tmp")
printf "text content" > "$writer"
if [[ -f "$KK_TEST_TMPDIR/create_text.tmp" && "$(cat "$KK_TEST_TMPDIR"/create_text.tmp)" == "text content" ]]; then
    kk_test_pass "Create new text file"
else
    kk_test_fail "Create new text file"
fi

# Test 2: Create existing file (should overwrite)
kk_test_start "Create text on existing file"
printf "old content" > "$KK_TEST_TMPDIR/overwrite_text.tmp"
writer=$(tfile.createText "$KK_TEST_TMPDIR/overwrite_text.tmp")
printf "new content" > "$writer"
if [[ "$(cat "$KK_TEST_TMPDIR"/overwrite_text.tmp)" == "new content" ]]; then
    kk_test_pass "Create text on existing file"
else
    kk_test_fail "Create text on existing file"
fi

# Test 3: Invalid path
kk_test_start "Create text with invalid path"
if ! writer=$(tfile.createText "/invalid/path/file.tmp" 2>&1); then
    kk_test_pass "Create text with invalid path (correctly failed)"
else
    kk_test_fail "Create text with invalid path (should have failed)"
fi
