#!/bin/bash
# 037_write_all_bytes.sh - Test TFile.WriteAllBytes method
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

# Test 1: Write bytes to new file
kt_test_start "Write bytes to new file"
bytes="Hello World"
result=$(tfile.writeAllBytes "$_KT_TMPDIR/writebytes.tmp" "$bytes")
if [[ -f "$_KT_TMPDIR/writebytes.tmp" && "$(cat "$_KT_TMPDIR"/writebytes.tmp)" == "$bytes" ]]; then
    kt_test_pass "Write bytes to new file"
else
    kt_test_fail "Write bytes to new file"
fi

# Test 2: Write bytes to existing file (overwrites)
kt_test_start "Write bytes to existing file"
echo "old" > "$_KT_TMPDIR/overwrite_bytes.tmp"
result=$(tfile.writeAllBytes "$_KT_TMPDIR/overwrite_bytes.tmp" "new")
if [[ "$(cat "$_KT_TMPDIR"/overwrite_bytes.tmp)" == "new" ]]; then
    kt_test_pass "Write bytes to existing file"
else
    kt_test_fail "Write bytes to existing file"
fi

# Test 3: Write empty bytes
kt_test_start "Write empty bytes"
result=$(tfile.writeAllBytes "$_KT_TMPDIR/empty_bytes.tmp" "")
if [[ -f "$_KT_TMPDIR/empty_bytes.tmp" && ! -s "$_KT_TMPDIR/empty_bytes.tmp" ]]; then
    kt_test_pass "Write empty bytes"
else
    kt_test_fail "Write empty bytes"
fi

# Test 4: Write to invalid path
kt_test_start "Write bytes to invalid path"
if ! result=$(tfile.writeAllBytes "/invalid/path/file.tmp" "content" 2>&1); then
    kt_test_pass "Write bytes to invalid path (correctly failed)"
else
    kt_test_fail "Write bytes to invalid path (should have failed)"
fi
