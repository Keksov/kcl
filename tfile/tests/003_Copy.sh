#!/bin/bash
# 003_copy.sh - Test TFile.Copy method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Copy existing file
test_start "Copy existing file"
echo "content" > test_source.tmp
result=$(tfile.copy "test_source.tmp" "test_dest.tmp")
if [[ -f "test_dest.tmp" && "$(cat test_dest.tmp)" == "content" ]]; then
    test_pass "Copy existing file"
else
    test_fail "Copy existing file"
fi

# Test 2: Copy with overwrite=false (default)
test_start "Copy with overwrite=false"
echo "dest" > test_dest2.tmp
if ! result=$(tfile.copy "test_source.tmp" "test_dest2.tmp" 2>&1); then
    test_pass "Copy with overwrite=false (correctly failed)"
else
    test_fail "Copy with overwrite=false (should have failed)"
fi

# Test 3: Copy with overwrite=true
test_start "Copy with overwrite=true"
result=$(tfile.copy "test_source.tmp" "test_dest2.tmp" true)
if [[ "$(cat test_dest2.tmp)" == "content" ]]; then
    test_pass "Copy with overwrite=true"
else
    test_fail "Copy with overwrite=true"
fi

# Test 4: Copy non-existing source
test_start "Copy non-existing source"
if ! result=$(tfile.copy "nonexist.tmp" "dest.tmp" 2>&1); then
    test_pass "Copy non-existing source (correctly failed)"
else
    test_fail "Copy non-existing source (should have failed)"
fi

# Test 5: Copy to invalid destination path
test_start "Copy to invalid path"
if ! result=$(tfile.copy "test_source.tmp" "/invalid/path/file.tmp" 2>&1); then
    test_pass "Copy to invalid path (correctly failed)"
else
    test_fail "Copy to invalid path (should have failed)"
fi

# Test 6: Copy empty file
test_start "Copy empty file"
touch test_empty.tmp
result=$(tfile.copy "test_empty.tmp" "test_empty_dest.tmp")
if [[ -f "test_empty_dest.tmp" && ! -s "test_empty_dest.tmp" ]]; then
    test_pass "Copy empty file"
else
    test_fail "Copy empty file"
fi
