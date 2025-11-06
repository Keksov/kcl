#!/bin/bash
# 029_replace.sh - Test TFile.Replace method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
TEST_ID=029
mkdir -p ".tmp/$TEST_ID"

# Test 1: Replace file contents with backup
test_start "Replace file contents with backup"
echo "old content" > ".tmp/$TEST_ID/replace_dest.tmp"
echo "new content" > ".tmp/$TEST_ID/replace_source.tmp"
result=$(tfile.replace ".tmp/$TEST_ID/replace_source.tmp" ".tmp/$TEST_ID/replace_dest.tmp" ".tmp/$TEST_ID/replace_backup.tmp")
if [[ "$(cat .tmp/$TEST_ID/replace_dest.tmp)" == "new content" && "$(cat .tmp/$TEST_ID/replace_backup.tmp)" == "old content" ]]; then
    test_pass "Replace file contents with backup"
else
    test_fail "Replace file contents with backup"
fi

# Test 2: Replace with IgnoreMetadataErrors
test_start "Replace with IgnoreMetadataErrors"
echo "old2" > ".tmp/$TEST_ID/replace_dest2.tmp"
echo "new2" > ".tmp/$TEST_ID/replace_source2.tmp"
result=$(tfile.replace ".tmp/$TEST_ID/replace_source2.tmp" ".tmp/$TEST_ID/replace_dest2.tmp" ".tmp/$TEST_ID/replace_backup2.tmp" true)
if [[ "$(cat .tmp/$TEST_ID/replace_dest2.tmp)" == "new2" ]]; then
    test_pass "Replace with IgnoreMetadataErrors"
else
    test_fail "Replace with IgnoreMetadataErrors"
fi

# Test 3: Replace non-existing source
test_start "Replace with non-existing source"
if ! result=$(tfile.replace ".tmp/$TEST_ID/nonexist.tmp" ".tmp/$TEST_ID/replace_dest.tmp" ".tmp/$TEST_ID/backup.tmp" 2>&1); then
    test_pass "Replace with non-existing source (correctly failed)"
else
    test_fail "Replace with non-existing source (should have failed)"
fi

# Test 4: Replace non-existing destination
test_start "Replace with non-existing destination"
echo "source" > ".tmp/$TEST_ID/replace_source3.tmp"
if ! result=$(tfile.replace ".tmp/$TEST_ID/replace_source3.tmp" ".tmp/$TEST_ID/nonexist.tmp" ".tmp/$TEST_ID/backup.tmp" 2>&1); then
    test_pass "Replace with non-existing destination (correctly failed)"
else
    test_fail "Replace with non-existing destination (should have failed)"
fi
