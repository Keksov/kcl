#!/bin/bash
# 029_replace.sh - Test TFile.Replace method
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

# Test 1: Replace file contents with backup
kk_test_start "Replace file contents with backup"
echo "old content" > "$KK_TEST_TMPDIR/replace_dest.tmp"
echo "new content" > "$KK_TEST_TMPDIR/replace_source.tmp"
result=$(tfile.replace "$KK_TEST_TMPDIR/replace_source.tmp" "$KK_TEST_TMPDIR/replace_dest.tmp" "$KK_TEST_TMPDIR/replace_backup.tmp")
if [[ "$(cat "$KK_TEST_TMPDIR"/replace_dest.tmp)" == "new content" && "$(cat "$KK_TEST_TMPDIR"/replace_backup.tmp)" == "old content" ]]; then
    kk_test_pass "Replace file contents with backup"
else
    kk_test_fail "Replace file contents with backup"
fi

# Test 2: Replace with IgnoreMetadataErrors
kk_test_start "Replace with IgnoreMetadataErrors"
echo "old2" > "$KK_TEST_TMPDIR/replace_dest2.tmp"
echo "new2" > "$KK_TEST_TMPDIR/replace_source2.tmp"
result=$(tfile.replace "$KK_TEST_TMPDIR/replace_source2.tmp" "$KK_TEST_TMPDIR/replace_dest2.tmp" "$KK_TEST_TMPDIR/replace_backup2.tmp" true)
if [[ "$(cat "$KK_TEST_TMPDIR"/replace_dest2.tmp)" == "new2" ]]; then
    kk_test_pass "Replace with IgnoreMetadataErrors"
else
    kk_test_fail "Replace with IgnoreMetadataErrors"
fi

# Test 3: Replace non-existing source
kk_test_start "Replace with non-existing source"
if ! result=$(tfile.replace "$KK_TEST_TMPDIR/nonexist.tmp" "$KK_TEST_TMPDIR/replace_dest.tmp" "$KK_TEST_TMPDIR/backup.tmp" 2>&1); then
    kk_test_pass "Replace with non-existing source (correctly failed)"
else
    kk_test_fail "Replace with non-existing source (should have failed)"
fi

# Test 4: Replace non-existing destination
kk_test_start "Replace with non-existing destination"
echo "source" > "$KK_TEST_TMPDIR/replace_source3.tmp"
if ! result=$(tfile.replace "$KK_TEST_TMPDIR/replace_source3.tmp" "$KK_TEST_TMPDIR/nonexist.tmp" "$KK_TEST_TMPDIR/backup.tmp" 2>&1); then
    kk_test_pass "Replace with non-existing destination (correctly failed)"
else
    kk_test_fail "Replace with non-existing destination (should have failed)"
fi
