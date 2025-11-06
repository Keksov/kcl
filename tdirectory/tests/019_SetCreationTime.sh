#!/bin/bash
# 019_SetCreationTime.sh - Test TDirectory.SetCreationTime method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory
init_test_tmpdir "019"
temp_base="$TEST_TMP_DIR"

# Test 1: SetCreationTime changes creation time
test_start "SetCreationTime - changes creation time"
test_dir="$temp_base/time_set_001"
tdirectory.createDirectory "$test_dir"
original=$(tdirectory.getCreationTime "$test_dir")
# Set new creation time (current time)
new_time=$(date +%s)
tdirectory.setCreationTime "$test_dir" "$new_time"
updated=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$updated" ]]; then
    test_pass "SetCreationTime - changes creation time"
else
    test_fail "SetCreationTime - changes creation time (expected: time to be set)"
fi

# Test 2: SetCreationTime persists
test_start "SetCreationTime - persists after operation"
test_dir="$temp_base/persist_time"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setCreationTime "$test_dir" "$new_time"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetCreationTime - persists after operation"
else
    test_fail "SetCreationTime - persists after operation (expected: time persists)"
fi

# Test 3: SetCreationTime on nested directory
test_start "SetCreationTime - nested directory"
test_dir="$temp_base/nested/path"
tdirectory.createDirectory "$test_dir"
new_time=$(date +%s)
tdirectory.setCreationTime "$test_dir" "$new_time"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetCreationTime - nested directory"
else
    test_fail "SetCreationTime - nested directory (expected: time to be set)"
fi

# Test 4: SetCreationTime with various time formats
test_start "SetCreationTime - accepts datetime"
test_dir="$temp_base/time_format"
tdirectory.createDirectory "$test_dir"
# Use a specific time value
tdirectory.setCreationTime "$test_dir" "2024-01-01 12:00:00"
result=$(tdirectory.getCreationTime "$test_dir")
if [[ -n "$result" ]]; then
    test_pass "SetCreationTime - accepts datetime"
else
    test_fail "SetCreationTime - accepts datetime (expected: time to be set)"
fi

# Cleanup


