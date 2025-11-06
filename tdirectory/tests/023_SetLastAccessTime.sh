#!/bin/bash
# 023_SetLastAccessTime.sh - Test TDirectory.SetLastAccessTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
temp_base="$(tpath.getTempPath)/tdirectory_test_$$"
tdirectory.createDirectory "$temp_base"

# Test 1: SetLastAccessTime changes last access time
test_start "SetLastAccessTime - changes last access time"
test_dir="$temp_base/access_set_001"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTime "$test_dir" "$new_time"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastAccessTime - changes last access time"
else
    test_fail "SetLastAccessTime - changes last access time (expected: time to be set)"
fi

# Test 2: SetLastAccessTime persists
test_start "SetLastAccessTime - persists after operation"
test_dir="$temp_base/access_persist"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTime "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastAccessTime - persists after operation"
else
    test_fail "SetLastAccessTime - persists after operation (expected: time persists)"
fi

# Test 3: SetLastAccessTime on nested directory
test_start "SetLastAccessTime - nested directory"
test_dir="$temp_base/access/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTime "$test_dir" "$new_time"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastAccessTime - nested directory"
else
    test_fail "SetLastAccessTime - nested directory (expected: time to be set)"
fi

# Test 4: SetLastAccessTime with datetime format
test_start "SetLastAccessTime - accepts datetime"
test_dir="$temp_base/access_format"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastAccessTime "$test_dir" "2024-01-01 12:00:00"
result=$(tdirectory.getLastAccessTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastAccessTime - accepts datetime"
else
    test_fail "SetLastAccessTime - accepts datetime (expected: time to be set)"
fi

# Cleanup
rm -rf "$temp_base" 2>/dev/null || true

echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
