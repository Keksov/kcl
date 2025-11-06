#!/bin/bash
# 029_replace.sh - Test TFile.Replace method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "029"

# Test 1: Replace file contents with backup
test_start "Replace file contents with backup"
echo "old content" > "$TEST_TMP_DIR/replace_dest.tmp"
echo "new content" > "$TEST_TMP_DIR/replace_source.tmp"
result=$(tfile.replace "$TEST_TMP_DIR/replace_source.tmp" "$TEST_TMP_DIR/replace_dest.tmp" "$TEST_TMP_DIR/replace_backup.tmp")
if [[ "$(cat "$TEST_TMP_DIR"/replace_dest.tmp)" == "new content" && "$(cat "$TEST_TMP_DIR"/replace_backup.tmp)" == "old content" ]]; then
    test_pass "Replace file contents with backup"
else
    test_fail "Replace file contents with backup"
fi

# Test 2: Replace with IgnoreMetadataErrors
test_start "Replace with IgnoreMetadataErrors"
echo "old2" > "$TEST_TMP_DIR/replace_dest2.tmp"
echo "new2" > "$TEST_TMP_DIR/replace_source2.tmp"
result=$(tfile.replace "$TEST_TMP_DIR/replace_source2.tmp" "$TEST_TMP_DIR/replace_dest2.tmp" "$TEST_TMP_DIR/replace_backup2.tmp" true)
if [[ "$(cat "$TEST_TMP_DIR"/replace_dest2.tmp)" == "new2" ]]; then
    test_pass "Replace with IgnoreMetadataErrors"
else
    test_fail "Replace with IgnoreMetadataErrors"
fi

# Test 3: Replace non-existing source
test_start "Replace with non-existing source"
if ! result=$(tfile.replace "$TEST_TMP_DIR/nonexist.tmp" "$TEST_TMP_DIR/replace_dest.tmp" "$TEST_TMP_DIR/backup.tmp" 2>&1); then
    test_pass "Replace with non-existing source (correctly failed)"
else
    test_fail "Replace with non-existing source (should have failed)"
fi

# Test 4: Replace non-existing destination
test_start "Replace with non-existing destination"
echo "source" > "$TEST_TMP_DIR/replace_source3.tmp"
if ! result=$(tfile.replace "$TEST_TMP_DIR/replace_source3.tmp" "$TEST_TMP_DIR/nonexist.tmp" "$TEST_TMP_DIR/backup.tmp" 2>&1); then
    test_pass "Replace with non-existing destination (correctly failed)"
else
    test_fail "Replace with non-existing destination (should have failed)"
fi
