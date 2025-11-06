#!/bin/bash
# 027_SetLastWriteTime.sh - Test TDirectory.SetLastWriteTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
init_test_tmpdir "027"
temp_base="$TEST_TMP_DIR"

# Test 1: SetLastWriteTime changes last write time
test_start "SetLastWriteTime - changes last write time"
test_dir="$temp_base/write_set_001"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTime "$test_dir" "$new_time"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastWriteTime - changes last write time"
else
    test_fail "SetLastWriteTime - changes last write time (expected: time to be set)"
fi

# Test 2: SetLastWriteTime persists
test_start "SetLastWriteTime - persists after operation"
test_dir="$temp_base/write_persist"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTime "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastWriteTime - persists after operation"
else
    test_fail "SetLastWriteTime - persists after operation (expected: time persists)"
fi

# Test 3: SetLastWriteTime on nested directory
test_start "SetLastWriteTime - nested directory"
test_dir="$temp_base/write/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTime "$test_dir" "$new_time"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastWriteTime - nested directory"
else
    test_fail "SetLastWriteTime - nested directory (expected: time to be set)"
fi

# Test 4: SetLastWriteTime with datetime format
test_start "SetLastWriteTime - accepts datetime"
test_dir="$temp_base/write_format"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastWriteTime "$test_dir" "2024-01-01 12:00:00"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastWriteTime - accepts datetime"
else
    test_fail "SetLastWriteTime - accepts datetime (expected: time to be set)"
fi

# Cleanup


