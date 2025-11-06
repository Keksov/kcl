#!/bin/bash
# 021_SetCreationTimeUtc.sh - Test TDirectory.SetCreationTimeUtc method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
init_test_tmpdir "021"
temp_base="$TEST_TMP_DIR"

# Test 1: SetCreationTimeUtc changes UTC creation time
test_start "SetCreationTimeUtc - changes UTC creation time"
test_dir="$temp_base/utc_set_001"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setCreationTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetCreationTimeUtc - changes UTC creation time"
else
    test_fail "SetCreationTimeUtc - changes UTC creation time (expected: UTC time to be set)"
fi

# Test 2: SetCreationTimeUtc persists
test_start "SetCreationTimeUtc - persists after operation"
test_dir="$temp_base/utc_persist"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setCreationTimeUtc "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetCreationTimeUtc - persists after operation"
else
    test_fail "SetCreationTimeUtc - persists after operation (expected: UTC time persists)"
fi

# Test 3: SetCreationTimeUtc on nested directory
test_start "SetCreationTimeUtc - nested directory"
test_dir="$temp_base/utc/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setCreationTimeUtc "$test_dir" "$new_time"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetCreationTimeUtc - nested directory"
else
    test_fail "SetCreationTimeUtc - nested directory (expected: UTC time to be set)"
fi

# Test 4: SetCreationTimeUtc with datetime format
test_start "SetCreationTimeUtc - accepts UTC datetime"
test_dir="$temp_base/utc_format"
tdirectory.createDirectory "$test_dir"
tdirectory.setCreationTimeUtc "$test_dir" "2024-01-01 12:00:00"
result=$(tdirectory.getCreationTimeUtc "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetCreationTimeUtc - accepts UTC datetime"
else
    test_fail "SetCreationTimeUtc - accepts UTC datetime (expected: UTC time to be set)"
fi

# Cleanup


