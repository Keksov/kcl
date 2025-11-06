#!/bin/bash
# 028_GetLastWriteTimeUtc.sh - Test TDirectory.GetLastWriteTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
init_test_tmpdir "028"
temp_base="$TEST_TMP_DIR"

# Test 1: GetLastWriteTimeUtc returns datetime
test_start "GetLastWriteTimeUtc - returns datetime value"
test_dir="$temp_base/utc_write_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetLastWriteTimeUtc - returns datetime value"
else
    test_fail "GetLastWriteTimeUtc - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetLastWriteTimeUtc on newly created directory
test_start "GetLastWriteTimeUtc - newly created directory"
test_dir="$temp_base/utc_write_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetLastWriteTimeUtc - newly created directory"
else
    test_fail "GetLastWriteTimeUtc - newly created directory (expected: valid datetime)"
fi

# Test 3: GetLastWriteTimeUtc consistency
test_start "GetLastWriteTimeUtc - consistent results"
test_dir="$temp_base/utc_write_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getLastWriteTimeUtc "$test_dir")
# Note: do not sleep between calls - filesystem metadata may be updated
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    test_pass "GetLastWriteTimeUtc - consistent results"
else
    test_fail "GetLastWriteTimeUtc - consistent results (expected same time)"
fi

# Test 4: GetLastWriteTimeUtc on nested directory
test_start "GetLastWriteTimeUtc - nested directory"
test_dir="$temp_base/utc/write/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetLastWriteTimeUtc - nested directory"
else
    test_fail "GetLastWriteTimeUtc - nested directory (expected: valid datetime)"
fi

# Cleanup


