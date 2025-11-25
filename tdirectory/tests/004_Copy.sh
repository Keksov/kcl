#!/bin/bash
# Copy
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Copy" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: Copy simple directory
kk_test_start "Copy - copy simple directory"
source_dir="$KK_TEST_TMPDIR/source_simple"
dest_dir="$KK_TEST_TMPDIR/dest_simple"
tdirectory.createDirectory "$source_dir"
echo "test content" > "$source_dir/file.txt"
tdirectory.copy "$source_dir" "$dest_dir"
if [[ -d "$dest_dir" && -f "$dest_dir/file.txt" ]]; then
    kk_test_pass "Copy - copy simple directory"
else
    kk_test_fail "Copy - copy simple directory (expected destination to exist with files)"
fi

# Test 2: Copy directory with subdirectories
kk_test_start "Copy - copy directory with subdirectories"
source_dir="$KK_TEST_TMPDIR/source_nested"
dest_dir="$KK_TEST_TMPDIR/dest_nested"
tdirectory.createDirectory "$source_dir/sub1/sub2"
echo "content" > "$source_dir/file.txt"
echo "content" > "$source_dir/sub1/file1.txt"
echo "content" > "$source_dir/sub1/sub2/file2.txt"
tdirectory.copy "$source_dir" "$dest_dir"
if [[ -d "$dest_dir/sub1/sub2" && -f "$dest_dir/sub1/sub2/file2.txt" ]]; then
    kk_test_pass "Copy - copy directory with subdirectories"
else
    kk_test_fail "Copy - copy directory with subdirectories (expected nested structure to be copied)"
fi

# Test 3: Copy directory with multiple files
kk_test_start "Copy - copy directory with multiple files"
source_dir="$KK_TEST_TMPDIR/source_multifile"
dest_dir="$KK_TEST_TMPDIR/dest_multifile"
tdirectory.createDirectory "$source_dir"
for i in {1..5}; do
    echo "file $i" > "$source_dir/file_$i.txt"
done
tdirectory.copy "$source_dir" "$dest_dir"
if [[ -d "$dest_dir" && -f "$dest_dir/file_1.txt" && -f "$dest_dir/file_5.txt" ]]; then
    kk_test_pass "Copy - copy directory with multiple files"
else
    kk_test_fail "Copy - copy directory with multiple files (expected all files to be copied)"
fi

# Test 4: Copied files are independent
kk_test_start "Copy - copied files are independent"
source_dir="$KK_TEST_TMPDIR/source_indep"
dest_dir="$KK_TEST_TMPDIR/dest_indep"
tdirectory.createDirectory "$source_dir"
echo "original" > "$source_dir/file.txt"
tdirectory.copy "$source_dir" "$dest_dir"
echo "modified" > "$dest_dir/file.txt"
source_content=$(cat "$source_dir/file.txt")
dest_content=$(cat "$dest_dir/file.txt")
if [[ "$source_content" == "original" && "$dest_content" == "modified" ]]; then
    kk_test_pass "Copy - copied files are independent"
else
    kk_test_fail "Copy - copied files are independent (expected separate file contents)"
fi

# Test 5: Copy directory with special characters in names
kk_test_start "Copy - copy directory with special characters"
source_dir="$KK_TEST_TMPDIR/source-special.dir"
dest_dir="$KK_TEST_TMPDIR/dest-special.dir"
tdirectory.createDirectory "$source_dir"
echo "content" > "$source_dir/file-with-dash.txt"
echo "content" > "$source_dir/file_with_underscore.txt"
tdirectory.copy "$source_dir" "$dest_dir"
if [[ -f "$dest_dir/file-with-dash.txt" && -f "$dest_dir/file_with_underscore.txt" ]]; then
    kk_test_pass "Copy - copy directory with special characters"
else
    kk_test_fail "Copy - copy directory with special characters (expected special char files to be copied)"
fi

# Test 6: Copy to directory with spaces in path
kk_test_start "Copy - copy to directory with spaces in path"
source_dir="$KK_TEST_TMPDIR/source_spaces"
dest_dir="$KK_TEST_TMPDIR/dest with spaces"
tdirectory.createDirectory "$source_dir"
echo "content" > "$source_dir/test.txt"
tdirectory.copy "$source_dir" "$dest_dir"
if [[ -d "$dest_dir" && -f "$dest_dir/test.txt" ]]; then
    kk_test_pass "Copy - copy to directory with spaces in path"
else
    kk_test_fail "Copy - copy to directory with spaces in path (expected copy to destination with spaces)"
fi

# Test 7: Copy preserves directory structure
kk_test_start "Copy - preserves directory structure"
source_dir="$KK_TEST_TMPDIR/source_struct"
dest_dir="$KK_TEST_TMPDIR/dest_struct"
tdirectory.createDirectory "$source_dir/a/b/c"
tdirectory.createDirectory "$source_dir/x/y/z"
echo "file" > "$source_dir/a/b/c/deep.txt"
echo "file" > "$source_dir/x/y/z/deep.txt"
tdirectory.copy "$source_dir" "$dest_dir"
if [[ -d "$dest_dir/a/b/c" && -d "$dest_dir/x/y/z" && -f "$dest_dir/a/b/c/deep.txt" && -f "$dest_dir/x/y/z/deep.txt" ]]; then
    kk_test_pass "Copy - preserves directory structure"
else
    kk_test_fail "Copy - preserves directory structure (expected complete structure to be preserved)"
fi

# Test 8: Copy empty directory
kk_test_start "Copy - copy empty directory"
source_dir="$KK_TEST_TMPDIR/source_empty"
dest_dir="$KK_TEST_TMPDIR/dest_empty"
tdirectory.createDirectory "$source_dir"
tdirectory.copy "$source_dir" "$dest_dir"
if [[ -d "$dest_dir" ]]; then
# Empty directories when copied should result in empty destination (or with only dir structure)
kk_test_pass "Copy - copy empty directory"
else
kk_test_fail "Copy - copy empty directory (expected destination directory to exist)"
fi

# Cleanup\nkk_fixture_teardown


