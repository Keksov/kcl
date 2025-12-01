#!/bin/bash
# 003_copy.sh - Test TFile.Copy method
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

# Test 1: Copy existing file
kt_test_start "Copy existing file"
printf "content" > "$_KT_TMPDIR/source.tmp"
tfile.copy "$_KT_TMPDIR/source.tmp" "$_KT_TMPDIR/dest.tmp" >/dev/null 2>&1
if [[ -f "$_KT_TMPDIR/dest.tmp" && "$(cat "$_KT_TMPDIR/dest.tmp")" == "content" ]]; then
    kt_test_pass "Copy existing file"
else
    kt_test_fail "Copy existing file"
fi

# Test 2: Copy with overwrite=false (default)
kt_test_start "Copy with overwrite=false"
printf "dest" > "$_KT_TMPDIR/dest2.tmp"
if tfile.copy "$_KT_TMPDIR/source.tmp" "$_KT_TMPDIR/dest2.tmp" >/dev/null 2>&1; then
    kt_test_fail "Copy with overwrite=false (should have failed)"
else
    kt_test_pass "Copy with overwrite=false (correctly failed)"
fi

# Test 3: Copy with overwrite=true
kt_test_start "Copy with overwrite=true"
tfile.copy "$_KT_TMPDIR/source.tmp" "$_KT_TMPDIR/dest2.tmp" true >/dev/null 2>&1
if [[ "$(cat "$_KT_TMPDIR/dest2.tmp")" == "content" ]]; then
    kt_test_pass "Copy with overwrite=true"
else
    kt_test_fail "Copy with overwrite=true"
fi

# Test 4: Copy non-existing source
kt_test_start "Copy non-existing source"
if tfile.copy "$_KT_TMPDIR/nonexist.tmp" "$_KT_TMPDIR/dest.tmp" >/dev/null 2>&1; then
    kt_test_fail "Copy non-existing source (should have failed)"
else
    kt_test_pass "Copy non-existing source (correctly failed)"
fi

# Test 5: Copy to invalid destination path
kt_test_start "Copy to invalid path"
if tfile.copy "$_KT_TMPDIR/source.tmp" "/invalid/path/file.tmp" >/dev/null 2>&1; then
    kt_test_fail "Copy to invalid path (should have failed)"
else
    kt_test_pass "Copy to invalid path (correctly failed)"
fi

# Test 6: Copy empty file
kt_test_start "Copy empty file"
touch "$_KT_TMPDIR/empty.tmp"
tfile.copy "$_KT_TMPDIR/empty.tmp" "$_KT_TMPDIR/empty_dest.tmp" >/dev/null 2>&1
if [[ -f "$_KT_TMPDIR/empty_dest.tmp" && ! -s "$_KT_TMPDIR/empty_dest.tmp" ]]; then
    kt_test_pass "Copy empty file"
else
    kt_test_fail "Copy empty file"
fi
