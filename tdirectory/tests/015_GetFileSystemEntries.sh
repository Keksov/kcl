#!/bin/bash
# GetFileSystemEntries
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetFileSystemEntries" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetFileSystemEntries basic listing (mixed files and dirs)
kt_test_start "GetFileSystemEntries - lists files and directories"
test_dir="$_KT_TMPDIR/mixed_001"
tdirectory.createDirectory "$test_dir"
tdirectory.createDirectory "$test_dir/subdir"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getFileSystemEntries "$test_dir")
if [[ "$result" =~ "subdir" && "$result" =~ "file.txt" ]]; then
    kt_test_pass "GetFileSystemEntries - lists files and directories"
else
    kt_test_fail "GetFileSystemEntries - lists files and directories (expected both files and dirs)"
fi

# Test 2: GetFileSystemEntries with search pattern
kt_test_start "GetFileSystemEntries - with search pattern"
test_dir="$_KT_TMPDIR/pattern_001"
tdirectory.createDirectory "$test_dir"
tdirectory.createDirectory "$test_dir/app_dir"
echo "test" > "$test_dir/app_file.txt"
echo "test" > "$test_dir/other.txt"
result=$(tdirectory.getFileSystemEntries "$test_dir" "*app*")
if [[ "$result" =~ "app_dir" && "$result" =~ "app_file.txt" && ! "$result" =~ "other.txt" ]]; then
    kt_test_pass "GetFileSystemEntries - with search pattern"
else
    kt_test_fail "GetFileSystemEntries - with search pattern (expected only *app* entries)"
fi

# Test 3: GetFileSystemEntries empty directory
kt_test_start "GetFileSystemEntries - empty directory"
test_dir="$_KT_TMPDIR/empty_entries"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getFileSystemEntries "$test_dir")
if [[ -z "$result" ]]; then
    kt_test_pass "GetFileSystemEntries - empty directory"
else
    kt_test_fail "GetFileSystemEntries - empty directory (expected empty result)"
fi

# Test 4: GetFileSystemEntries with directories only
kt_test_start "GetFileSystemEntries - directories only"
test_dir="$_KT_TMPDIR/dirs_only"
tdirectory.createDirectory "$test_dir"
tdirectory.createDirectory "$test_dir/dir1"
tdirectory.createDirectory "$test_dir/dir2"
result=$(tdirectory.getFileSystemEntries "$test_dir")
if [[ "$result" =~ "dir1" && "$result" =~ "dir2" ]]; then
    kt_test_pass "GetFileSystemEntries - directories only"
else
    kt_test_fail "GetFileSystemEntries - directories only (expected all directories)"
fi

# Test 5: GetFileSystemEntries with files only
kt_test_start "GetFileSystemEntries - files only"
test_dir="$_KT_TMPDIR/files_only"
tdirectory.createDirectory "$test_dir"
echo "content1" > "$test_dir/file1.txt"
echo "content2" > "$test_dir/file2.txt"
result=$(tdirectory.getFileSystemEntries "$test_dir")
if [[ "$result" =~ "file1.txt" && "$result" =~ "file2.txt" ]]; then
    kt_test_pass "GetFileSystemEntries - files only"
else
    kt_test_fail "GetFileSystemEntries - files only (expected all files)"
fi

# Test 6: GetFileSystemEntries with special characters
kt_test_start "GetFileSystemEntries - special characters"
test_dir="$_KT_TMPDIR/special_entries"
tdirectory.createDirectory "$test_dir"
tdirectory.createDirectory "$test_dir/dir-special"
echo "data" > "$test_dir/file_special.txt"
result=$(tdirectory.getFileSystemEntries "$test_dir")
if [[ "$result" =~ "dir-special" && "$result" =~ "file_special" ]]; then
    kt_test_pass "GetFileSystemEntries - special characters"
else
    kt_test_fail "GetFileSystemEntries - special characters (expected special char entries)"
fi

# Test 7: GetFileSystemEntries with nested structure (top-level only)
kt_test_start "GetFileSystemEntries - top-level only"
test_dir="$_KT_TMPDIR/nested_top"
tdirectory.createDirectory "$test_dir/level1/level2"
echo "test" > "$test_dir/root.txt"
echo "test" > "$test_dir/level1/nested.txt"
result=$(tdirectory.getFileSystemEntries "$test_dir" "*" "TopDirectoryOnly")
if [[ "$result" =~ "level1" && "$result" =~ "root.txt" ]]; then
    kt_test_pass "GetFileSystemEntries - top-level only"
else
    kt_test_fail "GetFileSystemEntries - top-level only (expected top-level entries)"
fi

# Test 8: GetFileSystemEntries recursive
kt_test_start "GetFileSystemEntries - recursive search"
test_dir="$_KT_TMPDIR/recursive_entries"
tdirectory.createDirectory "$test_dir/a/b/c"
echo "file" > "$test_dir/root.txt"
echo "file" > "$test_dir/a/file1.txt"
echo "file" > "$test_dir/a/b/file2.txt"
echo "file" > "$test_dir/a/b/c/file3.txt"
result=$(tdirectory.getFileSystemEntries "$test_dir" "*" "AllDirectories")
if [[ "$result" =~ "root.txt" && "$result" =~ "file1.txt" && "$result" =~ "file2.txt" && "$result" =~ "file3.txt" ]]; then
    kt_test_pass "GetFileSystemEntries - recursive search"
else
    kt_test_fail "GetFileSystemEntries - recursive search (expected all nested entries)"
fi

# Cleanup\nkt_fixture_teardown


