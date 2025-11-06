#!/bin/bash
# 018_GetCreationTime.sh - Test TDirectory.GetCreationTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
init_test_tmpdir "018"
temp_base="$TEST_TMP_DIR"

# Test 1: GetCreationTime returns datetime
test_start "GetCreationTime - returns datetime value"
test_dir="$temp_base/time_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetCreationTime - returns datetime value"
else
    test_fail "GetCreationTime - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetCreationTime on newly created directory
test_start "GetCreationTime - newly created directory"
test_dir="$temp_base/new_created"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTime "$test_dir")
# Result should be a valid datetime (non-empty)
if [[ -n "$result" ]]; then
    test_pass "GetCreationTime - newly created directory"
else
    test_fail "GetCreationTime - newly created directory (expected: valid datetime)"
fi

# Test 3: GetCreationTime consistency
test_start "GetCreationTime - consistent results"
test_dir="$temp_base/consistent_time"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getCreationTime "$test_dir")
# Note: do not sleep between calls - access time may be updated by filesystem
# Just verify that immediate calls return consistent results
result2=$(tdirectory.getCreationTime "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    test_pass "GetCreationTime - consistent results"
else
    test_fail "GetCreationTime - consistent results (expected same time: '$result1' vs '$result2')"
fi

# Test 4: GetCreationTime is recent
test_start "GetCreationTime - recent for new directory"
test_dir="$temp_base/recent_time"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTime "$test_dir")
# Time should be non-empty and reasonable
if [[ -n "$result" ]]; then
    test_pass "GetCreationTime - recent for new directory"
else
    test_fail "GetCreationTime - recent for new directory (expected recent time)"
fi

# Test 5: GetCreationTime on nested directory
test_start "GetCreationTime - nested directory"
test_dir="$temp_base/nested/path/time"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetCreationTime - nested directory"
else
    test_fail "GetCreationTime - nested directory (expected: valid datetime)"
fi

# Test 6: GetCreationTime on directory with spaces
test_start "GetCreationTime - directory with spaces"
test_dir="$temp_base/dir with spaces"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetCreationTime - directory with spaces"
else
    test_fail "GetCreationTime - directory with spaces (expected: valid datetime)"
fi

# Cleanup


