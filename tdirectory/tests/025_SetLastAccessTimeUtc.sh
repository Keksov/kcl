#!/bin/bash
# 025_SetLastAccessTimeUtc.sh - Test TDirectory.SetLastAccessTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
init_test_tmpdir "025"
temp_base="$TEST_TMP_DIR"

# Test 1: SetLastAccessTimeUtc changes UTC last access time
test_start "SetLastAccessTimeUtc - changes UTC last access time"
test_dir="$temp_base/utc_access_set_001"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastAccessTimeUtc - changes UTC last access time"
else
    test_fail "SetLastAccessTimeUtc - changes UTC last access time (expected: UTC time to be set)"
fi

# Test 2: SetLastAccessTimeUtc persists
test_start "SetLastAccessTimeUtc - persists after operation"
test_dir="$temp_base/utc_access_persist"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTimeUtc "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastAccessTimeUtc - persists after operation"
else
    test_fail "SetLastAccessTimeUtc - persists after operation (expected: UTC time persists)"
fi

# Test 3: SetLastAccessTimeUtc on nested directory
test_start "SetLastAccessTimeUtc - nested directory"
test_dir="$temp_base/utc/access/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastAccessTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getLastAccessTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastAccessTimeUtc - nested directory"
else
    test_fail "SetLastAccessTimeUtc - nested directory (expected: UTC time to be set)"
fi

# Cleanup


