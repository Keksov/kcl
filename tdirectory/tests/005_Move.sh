#!/bin/bash
# Move
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Move" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: Move simple directory
kt_test_start "Move - move simple directory"
source_dir="$_KT_TMPDIR/source_move"
dest_dir="$_KT_TMPDIR/dest_move"
tdirectory.createDirectory "$source_dir"
echo "content" > "$source_dir/file.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir" && -f "$dest_dir/file.txt" ]]; then
    kt_test_pass "Move - move simple directory"
else
    kt_test_fail "Move - move simple directory (expected source gone, destination exists with content)"
fi

# Test 2: Rename directory (move in same location)
kt_test_start "Move - rename directory"
source_dir="$_KT_TMPDIR/original_name"
dest_dir="$_KT_TMPDIR/renamed_name"
tdirectory.createDirectory "$source_dir"
echo "data" > "$source_dir/data.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir" && -f "$dest_dir/data.txt" ]]; then
    kt_test_pass "Move - rename directory"
else
    kt_test_fail "Move - rename directory (expected renaming to succeed)"
fi

# Test 3: Move directory with subdirectories
kt_test_start "Move - move directory with subdirectories"
source_dir="$_KT_TMPDIR/source_nested_move"
dest_dir="$_KT_TMPDIR/dest_nested_move"
tdirectory.createDirectory "$source_dir/sub1/sub2"
echo "file" > "$source_dir/sub1/sub2/test.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir/sub1/sub2" && -f "$dest_dir/sub1/sub2/test.txt" ]]; then
    kt_test_pass "Move - move directory with subdirectories"
else
    kt_test_fail "Move - move directory with subdirectories (expected nested structure to be moved)"
fi

# Test 4: Move directory to nested path
kt_test_start "Move - move directory to nested destination"
source_dir="$_KT_TMPDIR/source_to_nested"
dest_parent="$_KT_TMPDIR/parent_for_move"
tdirectory.createDirectory "$dest_parent"
tdirectory.createDirectory "$source_dir"
echo "content" > "$source_dir/file.txt"
dest_dir="$dest_parent/moved_dir"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir" && -f "$dest_dir/file.txt" ]]; then
    kt_test_pass "Move - move directory to nested destination"
else
    kt_test_fail "Move - move directory to nested destination (expected move to nested path)"
fi

# Test 5: Move preserves directory structure
kt_test_start "Move - preserves directory structure"
source_dir="$_KT_TMPDIR/source_struct_move"
dest_dir="$_KT_TMPDIR/dest_struct_move"
tdirectory.createDirectory "$source_dir/a/b/c"
tdirectory.createDirectory "$source_dir/x/y"
echo "file1" > "$source_dir/a/b/c/file.txt"
echo "file2" > "$source_dir/x/y/data.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir/a/b/c" && -d "$dest_dir/x/y" ]]; then
    kt_test_pass "Move - preserves directory structure"
else
    kt_test_fail "Move - preserves directory structure (expected complete structure preserved)"
fi

# Test 6: Move multiple files integrity
kt_test_start "Move - preserves multiple files"
source_dir="$_KT_TMPDIR/source_multifile_move"
dest_dir="$_KT_TMPDIR/dest_multifile_move"
tdirectory.createDirectory "$source_dir"
for i in {1..5}; do
    echo "file $i" > "$source_dir/file_$i.txt"
done
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -f "$dest_dir/file_1.txt" && -f "$dest_dir/file_5.txt" ]]; then
    kt_test_pass "Move - preserves multiple files"
else
    kt_test_fail "Move - preserves multiple files (expected all files to be moved)"
fi

# Test 7: Move directory with special characters
kt_test_start "Move - move directory with special characters"
source_dir="$_KT_TMPDIR/source-special.move"
dest_dir="$_KT_TMPDIR/dest-special.move"
tdirectory.createDirectory "$source_dir"
echo "content" > "$source_dir/file-name.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir" && -f "$dest_dir/file-name.txt" ]]; then
    kt_test_pass "Move - move directory with special characters"
else
    kt_test_fail "Move - move directory with special characters (expected move with special chars)"
fi

# Test 8: Move to path with spaces
kt_test_start "Move - move to path with spaces"
source_dir="$_KT_TMPDIR/source_spaces_move"
dest_dir="$_KT_TMPDIR/destination with spaces"
tdirectory.createDirectory "$source_dir"
echo "content" > "$source_dir/file.txt"
tdirectory.move "$source_dir" "$dest_dir"
if [[ ! -d "$source_dir" && -d "$dest_dir" && -f "$dest_dir/file.txt" ]]; then
    kt_test_pass "Move - move to path with spaces"
else
    kt_test_fail "Move - move to path with spaces (expected move to path with spaces)"
fi

# Cleanup\nkt_fixture_teardown


