#!/bin/bash
# 006_create_text.sh - Test TFile.CreateText method
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

# Test 1: Create new text file
kt_test_start "Create new text file"
writer=$(tfile.createText "$_KT_TMPDIR/create_text.tmp")
printf "text content" > "$writer"
if [[ -f "$_KT_TMPDIR/create_text.tmp" && "$(cat "$_KT_TMPDIR"/create_text.tmp)" == "text content" ]]; then
    kt_test_pass "Create new text file"
else
    kt_test_fail "Create new text file"
fi

# Test 2: Create existing file (should overwrite)
kt_test_start "Create text on existing file"
printf "old content" > "$_KT_TMPDIR/overwrite_text.tmp"
writer=$(tfile.createText "$_KT_TMPDIR/overwrite_text.tmp")
printf "new content" > "$writer"
if [[ "$(cat "$_KT_TMPDIR"/overwrite_text.tmp)" == "new content" ]]; then
    kt_test_pass "Create text on existing file"
else
    kt_test_fail "Create text on existing file"
fi

# Test 3: Invalid path
kt_test_start "Create text with invalid path"
if ! writer=$(tfile.createText "/invalid/path/file.tmp" 2>&1); then
    kt_test_pass "Create text with invalid path (correctly failed)"
else
    kt_test_fail "Create text with invalid path (should have failed)"
fi
