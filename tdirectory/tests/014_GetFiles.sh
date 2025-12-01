#!/bin/bash
# GetFiles
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetFiles" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetFiles basic listing
kt_test_start "GetFiles - basic file listing"
test_dir="$_KT_TMPDIR/files_basic"
tdirectory.createDirectory "$test_dir"
echo "file1" > "$test_dir/file1.txt"
echo "file2" > "$test_dir/file2.txt"
echo "file3" > "$test_dir/file3.txt"
result=$(tdirectory.getFiles "$test_dir")
if [[ "$result" =~ "file1.txt" && "$result" =~ "file2.txt" && "$result" =~ "file3.txt" ]]; then
    kt_test_pass "GetFiles - basic file listing"
else
    kt_test_fail "GetFiles - basic file listing (expected all files in output)"
fi

# Test 2: GetFiles excludes directories
kt_test_start "GetFiles - excludes directories"
test_dir="$_KT_TMPDIR/mixed_content"
tdirectory.createDirectory "$test_dir"
tdirectory.createDirectory "$test_dir/subdir"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getFiles "$test_dir")
if [[ "$result" =~ "file.txt" && ! "$result" =~ "subdir" ]]; then
    kt_test_pass "GetFiles - excludes directories"
else
    kt_test_fail "GetFiles - excludes directories (expected only files)"
fi

# Test 3: GetFiles with search pattern
kt_test_start "GetFiles - with search pattern"
test_dir="$_KT_TMPDIR/pattern"
tdirectory.createDirectory "$test_dir"
echo "test" > "$test_dir/doc1.txt"
echo "test" > "$test_dir/doc2.txt"
echo "test" > "$test_dir/readme.md"
result=$(tdirectory.getFiles "$test_dir" "*.txt")
if [[ "$result" =~ "doc1.txt" && "$result" =~ "doc2.txt" && ! "$result" =~ "readme.md" ]]; then
    kt_test_pass "GetFiles - with search pattern"
else
    kt_test_fail "GetFiles - with search pattern (expected only *.txt files)"
fi

# Test 4: GetFiles empty directory
kt_test_start "GetFiles - empty directory"
test_dir="$_KT_TMPDIR/empty_files"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getFiles "$test_dir")
if [[ -z "$result" ]]; then
    kt_test_pass "GetFiles - empty directory"
else
    kt_test_fail "GetFiles - empty directory (expected empty result)"
fi

# Test 5: GetFiles with TopDirectoryOnly (non-recursive)
kt_test_start "GetFiles - TopDirectoryOnly option"
test_dir="$_KT_TMPDIR/nested_files"
tdirectory.createDirectory "$test_dir/sub"
echo "root" > "$test_dir/root.txt"
echo "nested" > "$test_dir/sub/nested.txt"
result=$(tdirectory.getFiles "$test_dir" "*" "TopDirectoryOnly")
if [[ "$result" =~ "root.txt" && ! "$result" =~ "nested.txt" ]]; then
    kt_test_pass "GetFiles - TopDirectoryOnly option"
else
    kt_test_fail "GetFiles - TopDirectoryOnly option (expected only root.txt)"
fi

# Test 6: GetFiles with AllDirectories (recursive)
kt_test_start "GetFiles - AllDirectories recursive"
test_dir="$_KT_TMPDIR/recursive_files"
tdirectory.createDirectory "$test_dir/a/b"
echo "file" > "$test_dir/file1.txt"
echo "file" > "$test_dir/a/file2.txt"
echo "file" > "$test_dir/a/b/file3.txt"
result=$(tdirectory.getFiles "$test_dir" "*" "AllDirectories")
if [[ "$result" =~ "file1.txt" && "$result" =~ "file2.txt" && "$result" =~ "file3.txt" ]]; then
    kt_test_pass "GetFiles - AllDirectories recursive"
else
    kt_test_fail "GetFiles - AllDirectories recursive (expected all nested files)"
fi

# Test 7: GetFiles with multiple extensions
kt_test_start "GetFiles - multiple extension types"
test_dir="$_KT_TMPDIR/multi_ext"
tdirectory.createDirectory "$test_dir"
echo "data" > "$test_dir/file1.txt"
echo "data" > "$test_dir/file2.log"
echo "data" > "$test_dir/file3.tmp"
result=$(tdirectory.getFiles "$test_dir")
if [[ "$result" =~ "file1.txt" && "$result" =~ "file2.log" && "$result" =~ "file3.tmp" ]]; then
    kt_test_pass "GetFiles - multiple extension types"
else
    kt_test_fail "GetFiles - multiple extension types (expected all files)"
fi

# Test 8: GetFiles with special characters
kt_test_start "GetFiles - special characters in names"
test_dir="$_KT_TMPDIR/special"
tdirectory.createDirectory "$test_dir"
echo "data" > "$test_dir/file-with-dash.txt"
echo "data" > "$test_dir/file_with_underscore.txt"
result=$(tdirectory.getFiles "$test_dir")
if [[ "$result" =~ "file-with-dash.txt" && "$result" =~ "file_with_underscore.txt" ]]; then
    kt_test_pass "GetFiles - special characters in names"
else
    kt_test_fail "GetFiles - special characters in names (expected special char files)"
fi

# Cleanup\nkt_fixture_teardown


