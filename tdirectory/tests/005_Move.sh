#!/bin/bash
# Move
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Move" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Setup temp directory for tests
init_test_tmpdir "005"
temp_base="$TEST_TMP_DIR"

# Test 1: Move simple directory
kk_test_start "Move - move simple directory"
source_dir="$temp_base/source_move"
dest_dir="$temp_base/dest_move"
tdirectory.createDirectory "$source_dir"
echo "content" > "$source_dir/file.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir" && -f "$dest_dir/file.txt" ]]; then
    kk_test_pass "Move - move simple directory"
else
    kk_test_fail "Move - move simple directory (expected source gone, destination exists with content)"
fi

# Test 2: Rename directory (move in same location)
kk_test_start "Move - rename directory"
source_dir="$temp_base/original_name"
dest_dir="$temp_base/renamed_name"
tdirectory.createDirectory "$source_dir"
echo "data" > "$source_dir/data.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir" && -f "$dest_dir/data.txt" ]]; then
    kk_test_pass "Move - rename directory"
else
    kk_test_fail "Move - rename directory (expected renaming to succeed)"
fi

# Test 3: Move directory with subdirectories
kk_test_start "Move - move directory with subdirectories"
source_dir="$temp_base/source_nested_move"
dest_dir="$temp_base/dest_nested_move"
tdirectory.createDirectory "$source_dir/sub1/sub2"
echo "file" > "$source_dir/sub1/sub2/test.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir/sub1/sub2" && -f "$dest_dir/sub1/sub2/test.txt" ]]; then
    kk_test_pass "Move - move directory with subdirectories"
else
    kk_test_fail "Move - move directory with subdirectories (expected nested structure to be moved)"
fi

# Test 4: Move directory to nested path
kk_test_start "Move - move directory to nested destination"
source_dir="$temp_base/source_to_nested"
dest_parent="$temp_base/parent_for_move"
tdirectory.createDirectory "$dest_parent"
tdirectory.createDirectory "$source_dir"
echo "content" > "$source_dir/file.txt"
dest_dir="$dest_parent/moved_dir"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir" && -f "$dest_dir/file.txt" ]]; then
    kk_test_pass "Move - move directory to nested destination"
else
    kk_test_fail "Move - move directory to nested destination (expected move to nested path)"
fi

# Test 5: Move preserves directory structure
kk_test_start "Move - preserves directory structure"
source_dir="$temp_base/source_struct_move"
dest_dir="$temp_base/dest_struct_move"
tdirectory.createDirectory "$source_dir/a/b/c"
tdirectory.createDirectory "$source_dir/x/y"
echo "file1" > "$source_dir/a/b/c/file.txt"
echo "file2" > "$source_dir/x/y/data.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir/a/b/c" && -d "$dest_dir/x/y" ]]; then
    kk_test_pass "Move - preserves directory structure"
else
    kk_test_fail "Move - preserves directory structure (expected complete structure preserved)"
fi

# Test 6: Move multiple files integrity
kk_test_start "Move - preserves multiple files"
source_dir="$temp_base/source_multifile_move"
dest_dir="$temp_base/dest_multifile_move"
tdirectory.createDirectory "$source_dir"
for i in {1..5}; do
    echo "file $i" > "$source_dir/file_$i.txt"
done
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -f "$dest_dir/file_1.txt" && -f "$dest_dir/file_5.txt" ]]; then
    kk_test_pass "Move - preserves multiple files"
else
    kk_test_fail "Move - preserves multiple files (expected all files to be moved)"
fi

# Test 7: Move directory with special characters
kk_test_start "Move - move directory with special characters"
source_dir="$temp_base/source-special.move"
dest_dir="$temp_base/dest-special.move"
tdirectory.createDirectory "$source_dir"
echo "content" > "$source_dir/file-name.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir" && -f "$dest_dir/file-name.txt" ]]; then
    kk_test_pass "Move - move directory with special characters"
else
    kk_test_fail "Move - move directory with special characters (expected move with special chars)"
fi

# Test 8: Move to path with spaces
kk_test_start "Move - move to path with spaces"
source_dir="$temp_base/source_spaces_move"
dest_dir="$temp_base/destination with spaces"
tdirectory.createDirectory "$source_dir"
echo "content" > "$source_dir/file.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir" && -f "$dest_dir/file.txt" ]]; then
    kk_test_pass "Move - move to path with spaces"
else
    kk_test_fail "Move - move to path with spaces (expected move to path with spaces)"
fi

# Cleanup


