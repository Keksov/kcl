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

tdirectory_test_expect_lines() {
    local test_name="$1"
    local actual="$2"
    shift 2

    local expected=""
    local expected_line
    for expected_line in "$@"; do
        if [[ -n "$expected" ]]; then
            expected+=$'\n'
        fi
        expected+="$expected_line"
    done

    if [[ "$actual" == "$expected" ]]; then
        kt_test_pass "$test_name"
    else
        kt_test_fail "$test_name (expected exact result: '$expected', got: '$actual')"
    fi
}

# Test 1: GetFiles basic listing
kt_test_start "GetFiles - basic file listing"
test_dir="$_KT_TMPDIR/files_basic"
tdirectory.createDirectory "$test_dir"
echo "file1" > "$test_dir/file1.txt"
echo "file2" > "$test_dir/file2.txt"
echo "file3" > "$test_dir/file3.txt"
result=$(tdirectory.getFiles "$test_dir")
tdirectory_test_expect_lines "GetFiles - basic file listing" "$result" "$test_dir/file1.txt" "$test_dir/file2.txt" "$test_dir/file3.txt"

# Test 2: GetFiles excludes directories
kt_test_start "GetFiles - excludes directories"
test_dir="$_KT_TMPDIR/mixed_content"
tdirectory.createDirectory "$test_dir"
tdirectory.createDirectory "$test_dir/subdir"
echo "file" > "$test_dir/file.txt"
result=$(tdirectory.getFiles "$test_dir")
tdirectory_test_expect_lines "GetFiles - excludes directories" "$result" "$test_dir/file.txt"

# Test 3: GetFiles with search pattern
kt_test_start "GetFiles - with search pattern"
test_dir="$_KT_TMPDIR/pattern"
tdirectory.createDirectory "$test_dir"
echo "test" > "$test_dir/doc1.txt"
echo "test" > "$test_dir/doc2.txt"
echo "test" > "$test_dir/readme.md"
result=$(tdirectory.getFiles "$test_dir" "*.txt")
tdirectory_test_expect_lines "GetFiles - with search pattern" "$result" "$test_dir/doc1.txt" "$test_dir/doc2.txt"

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
tdirectory_test_expect_lines "GetFiles - TopDirectoryOnly option" "$result" "$test_dir/root.txt"

# Test 6: GetFiles with AllDirectories (recursive)
kt_test_start "GetFiles - AllDirectories recursive"
test_dir="$_KT_TMPDIR/recursive_files"
tdirectory.createDirectory "$test_dir/a/b"
echo "file" > "$test_dir/file1.txt"
echo "file" > "$test_dir/a/file2.txt"
echo "file" > "$test_dir/a/b/file3.txt"
result=$(tdirectory.getFiles "$test_dir" "*" "AllDirectories")
tdirectory_test_expect_lines "GetFiles - AllDirectories recursive" "$result" "$test_dir/a/b/file3.txt" "$test_dir/a/file2.txt" "$test_dir/file1.txt"

# Test 7: GetFiles with multiple extensions
kt_test_start "GetFiles - multiple extension types"
test_dir="$_KT_TMPDIR/multi_ext"
tdirectory.createDirectory "$test_dir"
echo "data" > "$test_dir/file1.txt"
echo "data" > "$test_dir/file2.log"
echo "data" > "$test_dir/file3.tmp"
result=$(tdirectory.getFiles "$test_dir")
tdirectory_test_expect_lines "GetFiles - multiple extension types" "$result" "$test_dir/file1.txt" "$test_dir/file2.log" "$test_dir/file3.tmp"

# Test 8: GetFiles with special characters
kt_test_start "GetFiles - special characters in names"
test_dir="$_KT_TMPDIR/special"
tdirectory.createDirectory "$test_dir"
echo "data" > "$test_dir/file-with-dash.txt"
echo "data" > "$test_dir/file_with_underscore.txt"
result=$(tdirectory.getFiles "$test_dir")
tdirectory_test_expect_lines "GetFiles - special characters in names" "$result" "$test_dir/file_with_underscore.txt" "$test_dir/file-with-dash.txt"

# Cleanup\nkt_fixture_teardown


