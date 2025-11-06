#!/bin/bash
# 002_Delete.sh - Test TDirectory.Delete method (both overloads)

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory for tests
temp_base="$(tpath.getTempPath)/tdirectory_test_$$"
tdirectory.createDirectory "$temp_base"

# Test 1: Delete empty directory
test_start "Delete - delete empty directory"
test_dir="$temp_base/empty_dir"
tdirectory.createDirectory "$test_dir"
tdirectory.delete "$test_dir"
if [[ ! -d "$test_dir" ]]; then
    test_pass "Delete - delete empty directory"
else
    test_fail "Delete - delete empty directory (expected directory to be deleted)"
fi

# Test 2: Delete empty directory with explicit Recursive=false
test_start "Delete - delete empty directory with Recursive false"
test_dir="$temp_base/empty_dir_explicit"
tdirectory.createDirectory "$test_dir"
tdirectory.delete "$test_dir" "false"
if [[ ! -d "$test_dir" ]]; then
    test_pass "Delete - delete empty directory with Recursive false"
else
    test_fail "Delete - delete empty directory with Recursive false (expected directory to be deleted)"
fi

# Test 3: Non-empty directory with Recursive=false should fail or not delete
test_start "Delete - non-empty directory with Recursive false fails gracefully"
test_dir="$temp_base/nonempty_dir"
tdirectory.createDirectory "$test_dir"
echo "content" > "$test_dir/file.txt"
tdirectory.delete "$test_dir" "false" 2>/dev/null || true
if [[ -d "$test_dir" ]]; then
    test_pass "Delete - non-empty directory with Recursive false fails gracefully"
else
    test_fail "Delete - non-empty directory with Recursive false fails gracefully (should not delete non-empty directory)"
fi

# Test 4: Non-empty directory with Recursive=true should delete
test_start "Delete - non-empty directory with Recursive true"
test_dir="$temp_base/nonempty_dir_recursive"
tdirectory.createDirectory "$test_dir/subdir"
echo "content" > "$test_dir/file.txt"
echo "content" > "$test_dir/subdir/file.txt"
tdirectory.delete "$test_dir" "true"
if [[ ! -d "$test_dir" ]]; then
    test_pass "Delete - non-empty directory with Recursive true"
else
    test_fail "Delete - non-empty directory with Recursive true (expected directory and contents to be deleted)"
fi

# Test 5: Delete directory with multiple levels of nesting
test_start "Delete - delete deeply nested directory tree"
test_dir="$temp_base/deep_tree"
tdirectory.createDirectory "$test_dir/a/b/c/d/e"
echo "test" > "$test_dir/a/file1.txt"
echo "test" > "$test_dir/a/b/file2.txt"
echo "test" > "$test_dir/a/b/c/file3.txt"
tdirectory.delete "$test_dir" "true"
if [[ ! -d "$test_dir" ]]; then
    test_pass "Delete - delete deeply nested directory tree"
else
    test_fail "Delete - delete deeply nested directory tree (expected entire tree to be deleted)"
fi

# Test 6: Delete directory with special files
test_start "Delete - delete directory with various file types"
test_dir="$temp_base/special_files"
tdirectory.createDirectory "$test_dir"
touch "$test_dir/regular.txt"
touch "$test_dir/empty_file"
echo "content" > "$test_dir/file_with_content.txt"
tdirectory.delete "$test_dir" "true"
if [[ ! -d "$test_dir" ]]; then
    test_pass "Delete - delete directory with various file types"
else
    test_fail "Delete - delete directory with various file types (expected all files and directory to be deleted)"
fi

# Test 7: Delete directory and verify with Exists
test_start "Delete - directory does not exist after deletion"
test_dir="$temp_base/verify_delete"
tdirectory.createDirectory "$test_dir"
tdirectory.delete "$test_dir"
if ! tdirectory.exists "$test_dir"; then
    test_pass "Delete - directory does not exist after deletion"
else
    test_fail "Delete - directory does not exist after deletion (expected Exists to return false)"
fi

# Test 8: Multiple sequential deletes
test_start "Delete - delete multiple directories in sequence"
success=true
for i in {1..3}; do
    test_dir="$temp_base/sequential_$i"
    tdirectory.createDirectory "$test_dir"
    tdirectory.delete "$test_dir"
    if [[ -d "$test_dir" ]]; then
        success=false
        break
    fi
done
if [[ "$success" == "true" ]]; then
    test_pass "Delete - delete multiple directories in sequence"
else
    test_fail "Delete - delete multiple directories in sequence (some directories were not deleted)"
fi

# Cleanup
rm -rf "$temp_base" 2>/dev/null || true

echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
