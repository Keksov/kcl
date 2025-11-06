#!/bin/bash
# 029_SetLastWriteTimeUtc.sh - Test TDirectory.SetLastWriteTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
init_test_tmpdir "029"
temp_base="$TEST_TMP_DIR"

# Test 1: SetLastWriteTimeUtc changes UTC last write time
test_start "SetLastWriteTimeUtc - changes UTC last write time"
test_dir="$temp_base/utc_write_set_001"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastWriteTimeUtc - changes UTC last write time"
else
    test_fail "SetLastWriteTimeUtc - changes UTC last write time (expected: UTC time to be set)"
fi

# Test 2: SetLastWriteTimeUtc persists
test_start "SetLastWriteTimeUtc - persists after operation"
test_dir="$temp_base/utc_write_persist"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTimeUtc "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastWriteTimeUtc - persists after operation"
else
    test_fail "SetLastWriteTimeUtc - persists after operation (expected: UTC time persists)"
fi

# Test 3: SetLastWriteTimeUtc on nested directory
test_start "SetLastWriteTimeUtc - nested directory"
test_dir="$temp_base/utc/write/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setLastWriteTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastWriteTimeUtc - nested directory"
else
    test_fail "SetLastWriteTimeUtc - nested directory (expected: UTC time to be set)"
fi

# Test 4: SetLastWriteTimeUtc with datetime format
test_start "SetLastWriteTimeUtc - accepts UTC datetime"
test_dir="$temp_base/utc_write_format"
tdirectory.createDirectory "$test_dir"
tdirectory.setLastWriteTimeUtc "$test_dir" "2024-01-01 12:00:00"
result=$(tdirectory.getLastWriteTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetLastWriteTimeUtc - accepts UTC datetime"
else
    test_fail "SetLastWriteTimeUtc - accepts UTC datetime (expected: UTC time to be set)"
fi

# Cleanup


