#!/bin/bash
# 024_GetLastAccessTimeUtc.sh - Test TDirectory.GetLastAccessTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
temp_base="$(tpath.getTempPath)/tdirectory_test_$$"
tdirectory.createDirectory "$temp_base"

# Test 1: GetLastAccessTimeUtc returns datetime
test_start "GetLastAccessTimeUtc - returns datetime value"
test_dir="$temp_base/utc_access_001"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetLastAccessTimeUtc - returns datetime value"
else
    test_fail "GetLastAccessTimeUtc - returns datetime value (expected: non-empty datetime)"
fi

# Test 2: GetLastAccessTimeUtc on newly created directory
test_start "GetLastAccessTimeUtc - newly created directory"
test_dir="$temp_base/utc_access_new"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetLastAccessTimeUtc - newly created directory"
else
    test_fail "GetLastAccessTimeUtc - newly created directory (expected: valid datetime)"
fi

# Test 3: GetLastAccessTimeUtc consistency
test_start "GetLastAccessTimeUtc - consistent results"
test_dir="$temp_base/utc_access_consistent"
tdirectory.createDirectory "$test_dir"
result1=$(tdirectory.getLastAccessTimeUtc "$test_dir")
sleep 1
result2=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ "$result1" == "$result2" ]]; then
    test_pass "GetLastAccessTimeUtc - consistent results"
else
    test_fail "GetLastAccessTimeUtc - consistent results (expected same time)"
fi

# Test 4: GetLastAccessTimeUtc on nested directory
test_start "GetLastAccessTimeUtc - nested directory"
test_dir="$temp_base/utc/access/nested/path"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "GetLastAccessTimeUtc - nested directory"
else
    test_fail "GetLastAccessTimeUtc - nested directory (expected: valid datetime)"
fi

# Cleanup
rm -rf "$temp_base" 2>/dev/null || true

echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
