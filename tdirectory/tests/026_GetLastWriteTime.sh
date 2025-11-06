#!/bin/bash
# 026_GetLastWriteTime.sh - Test TDirectory.GetLastWriteTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
init_test_tmpdir "026"
temp_base="$TEST_TMP_DIR"

# Test 1: GetLastWriteTime returns datetime
test_start "GetLastWriteTime - returns datetime value"
test_dir="$temp_base/write_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetLastWriteTime - returns datetime value"
else
    test_fail "GetLastWriteTime - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetLastWriteTime on newly created directory
test_start "GetLastWriteTime - newly created directory"
test_dir="$temp_base/write_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetLastWriteTime - newly created directory"
else
    test_fail "GetLastWriteTime - newly created directory (expected: valid datetime)"
fi

# Test 3: GetLastWriteTime consistency
test_start "GetLastWriteTime - consistent results"
test_dir="$temp_base/write_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getLastWriteTime "$test_dir")
# Note: do not sleep between calls - filesystem metadata may be updated
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getLastWriteTime "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    test_pass "GetLastWriteTime - consistent results"
else
    test_fail "GetLastWriteTime - consistent results (expected same time)"
fi

# Test 4: GetLastWriteTime on nested directory
test_start "GetLastWriteTime - nested directory"
test_dir="$temp_base/write/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetLastWriteTime - nested directory"
else
    test_fail "GetLastWriteTime - nested directory (expected: valid datetime)"
fi

# Test 5: GetLastWriteTime with spaces in path
test_start "GetLastWriteTime - directory with spaces"
test_dir="$temp_base/write dir with spaces"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetLastWriteTime - directory with spaces"
else
    test_fail "GetLastWriteTime - directory with spaces (expected: valid datetime)"
fi

# Cleanup


