#!/bin/bash
# 020_GetCreationTimeUtc.sh - Test TDirectory.GetCreationTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
temp_base="$(tpath.getTempPath)/tdirectory_test_$$"
tdirectory.createDirectory "$temp_base"

# Test 1: GetCreationTimeUtc returns datetime
test_start "GetCreationTimeUtc - returns datetime value"
test_dir="$temp_base/utc_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetCreationTimeUtc - returns datetime value"
else
    test_fail "GetCreationTimeUtc - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetCreationTimeUtc on newly created directory
test_start "GetCreationTimeUtc - newly created directory"
test_dir="$temp_base/utc_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetCreationTimeUtc - newly created directory"
else
    test_fail "GetCreationTimeUtc - newly created directory (expected: valid datetime)"
fi

# Test 3: GetCreationTimeUtc consistency
test_start "GetCreationTimeUtc - consistent results"
test_dir="$temp_base/utc_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getCreationTimeUtc "$test_dir")
sleep 1
result2=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    test_pass "GetCreationTimeUtc - consistent results"
else
    test_fail "GetCreationTimeUtc - consistent results (expected same time)"
fi

# Test 4: GetCreationTimeUtc on nested directory
test_start "GetCreationTimeUtc - nested directory"
test_dir="$temp_base/utc/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetCreationTimeUtc - nested directory"
else
    test_fail "GetCreationTimeUtc - nested directory (expected: valid datetime)"
fi

# Test 5: GetCreationTimeUtc with spaces in path
test_start "GetCreationTimeUtc - directory with spaces"
test_dir="$temp_base/utc dir with spaces"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetCreationTimeUtc - directory with spaces"
else
    test_fail "GetCreationTimeUtc - directory with spaces (expected: valid datetime)"
fi

# Cleanup
rm -rf "$temp_base" 2>/dev/null || true

echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
