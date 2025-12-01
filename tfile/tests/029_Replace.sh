#!/bin/bash
# 029_replace.sh - Test TFile.Replace method
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

# Test 1: Replace file contents with backup
kt_test_start "Replace file contents with backup"
echo "old content" > "$_KT_TMPDIR/replace_dest.tmp"
echo "new content" > "$_KT_TMPDIR/replace_source.tmp"
result=$(tfile.replace "$_KT_TMPDIR/replace_source.tmp" "$_KT_TMPDIR/replace_dest.tmp" "$_KT_TMPDIR/replace_backup.tmp")
if [[ "$(cat "$_KT_TMPDIR"/replace_dest.tmp)" == "new content" && "$(cat "$_KT_TMPDIR"/replace_backup.tmp)" == "old content" ]]; then
    kt_test_pass "Replace file contents with backup"
else
    kt_test_fail "Replace file contents with backup"
fi

# Test 2: Replace with IgnoreMetadataErrors
kt_test_start "Replace with IgnoreMetadataErrors"
echo "old2" > "$_KT_TMPDIR/replace_dest2.tmp"
echo "new2" > "$_KT_TMPDIR/replace_source2.tmp"
result=$(tfile.replace "$_KT_TMPDIR/replace_source2.tmp" "$_KT_TMPDIR/replace_dest2.tmp" "$_KT_TMPDIR/replace_backup2.tmp" true)
if [[ "$(cat "$_KT_TMPDIR"/replace_dest2.tmp)" == "new2" ]]; then
    kt_test_pass "Replace with IgnoreMetadataErrors"
else
    kt_test_fail "Replace with IgnoreMetadataErrors"
fi

# Test 3: Replace non-existing source
kt_test_start "Replace with non-existing source"
if ! result=$(tfile.replace "$_KT_TMPDIR/nonexist.tmp" "$_KT_TMPDIR/replace_dest.tmp" "$_KT_TMPDIR/backup.tmp" 2>&1); then
    kt_test_pass "Replace with non-existing source (correctly failed)"
else
    kt_test_fail "Replace with non-existing source (should have failed)"
fi

# Test 4: Replace non-existing destination
kt_test_start "Replace with non-existing destination"
echo "source" > "$_KT_TMPDIR/replace_source3.tmp"
if ! result=$(tfile.replace "$_KT_TMPDIR/replace_source3.tmp" "$_KT_TMPDIR/nonexist.tmp" "$_KT_TMPDIR/backup.tmp" 2>&1); then
    kt_test_pass "Replace with non-existing destination (correctly failed)"
else
    kt_test_fail "Replace with non-existing destination (should have failed)"
fi
