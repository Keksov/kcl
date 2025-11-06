#!/bin/bash
# 006_IsEmpty.sh - Test TDirectory.IsEmpty method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory for tests
init_test_tmpdir "006"
temp_base="$TEST_TMP_DIR"

# Test 1: Empty directory
test_start "IsEmpty - empty directory returns true"
test_dir="$temp_base/empty"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "true" ]]; then
    test_pass "IsEmpty - empty directory returns true"
else
    test_fail "IsEmpty - empty directory returns true (expected: true, got: '$result')"
fi

# Test 2: Directory with files
test_start "IsEmpty - directory with files returns false"
test_dir="$temp_base/with_files"
tdirectory.createDirectory "$test_dir"
echo "content" > "$test_dir/file.txt"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - directory with files returns false"
else
    test_fail "IsEmpty - directory with files returns false (expected: false, got: '$result')"
fi

# Test 3: Directory with subdirectories
test_start "IsEmpty - directory with subdirectories returns false"
test_dir="$temp_base/with_subdirs"
tdirectory.createDirectory "$test_dir/subdir"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - directory with subdirectories returns false"
else
    test_fail "IsEmpty - directory with subdirectories returns false (expected: false, got: '$result')"
fi

# Test 4: Empty path returns false
test_start "IsEmpty - empty path returns false"
result=$(tdirectory.isEmpty "")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - empty path returns false"
else
    test_fail "IsEmpty - empty path returns false (expected: false, got: '$result')"
fi

# Test 5: Directory with many files
test_start "IsEmpty - directory with many files"
test_dir="$temp_base/many_files"
tdirectory.createDirectory "$test_dir"
for i in {1..10}; do
    echo "file" > "$test_dir/file_$i.txt"
done
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - directory with many files"
else
    test_fail "IsEmpty - directory with many files (expected: false, got: '$result')"
fi

# Test 6: Directory emptied becomes empty
test_start "IsEmpty - directory becomes empty after file deletion"
test_dir="$temp_base/to_empty"
tdirectory.createDirectory "$test_dir"
echo "content" > "$test_dir/file.txt"
rm "$test_dir/file.txt"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "true" ]]; then
    test_pass "IsEmpty - directory becomes empty after file deletion"
else
    test_fail "IsEmpty - directory becomes empty after file deletion (expected: true after deletion)"
fi

# Test 7: Newly created directory is empty
test_start "IsEmpty - newly created directory is empty"
test_dir="$temp_base/newly_created"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "true" ]]; then
    test_pass "IsEmpty - newly created directory is empty"
else
    test_fail "IsEmpty - newly created directory is empty (expected: true, got: '$result')"
fi

# Test 8: Directory with nested empty subdirectories
test_start "IsEmpty - directory with nested empty subdirectories returns false"
test_dir="$temp_base/nested_empty_subdirs"
tdirectory.createDirectory "$test_dir/sub1/sub2/sub3"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "false" ]]; then
    test_pass "IsEmpty - directory with nested empty subdirectories returns false"
else
    test_fail "IsEmpty - directory with nested empty subdirectories returns false (expected: false)"
fi

# Cleanup


