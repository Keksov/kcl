#!/bin/bash
# 029_replace.sh - Test TFile.Replace method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Replace file contents with backup
test_start "Replace file contents with backup"
echo "old content" > test_replace_dest.tmp
echo "new content" > test_replace_source.tmp
result=$(tfile.replace "test_replace_source.tmp" "test_replace_dest.tmp" "test_replace_backup.tmp")
if [[ "$(cat test_replace_dest.tmp)" == "new content" && "$(cat test_replace_backup.tmp)" == "old content" ]]; then
    test_pass "Replace file contents with backup"
else
    test_fail "Replace file contents with backup"
fi

# Test 2: Replace with IgnoreMetadataErrors
test_start "Replace with IgnoreMetadataErrors"
echo "old2" > test_replace_dest2.tmp
echo "new2" > test_replace_source2.tmp
result=$(tfile.replace "test_replace_source2.tmp" "test_replace_dest2.tmp" "test_replace_backup2.tmp" true)
if [[ "$(cat test_replace_dest2.tmp)" == "new2" ]]; then
    test_pass "Replace with IgnoreMetadataErrors"
else
    test_fail "Replace with IgnoreMetadataErrors"
fi

# Test 3: Replace non-existing source
test_start "Replace with non-existing source"
if ! result=$(tfile.replace "nonexist.tmp" "test_replace_dest.tmp" "backup.tmp" 2>&1); then
    test_pass "Replace with non-existing source (correctly failed)"
else
    test_fail "Replace with non-existing source (should have failed)"
fi

# Test 4: Replace non-existing destination
test_start "Replace with non-existing destination"
echo "source" > test_replace_source3.tmp
if ! result=$(tfile.replace "test_replace_source3.tmp" "nonexist.tmp" "backup.tmp" 2>&1); then
    test_pass "Replace with non-existing destination (correctly failed)"
else
    test_fail "Replace with non-existing destination (should have failed)"
fi
